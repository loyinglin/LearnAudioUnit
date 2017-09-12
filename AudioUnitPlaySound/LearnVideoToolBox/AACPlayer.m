//
//  AACPlayer.m
//  LearnVideoToolBox
//
//  Created by 林伟池 on 16/9/9.
//  Copyright © 2016年 林伟池. All rights reserved.
//

#import "AACPlayer.h"
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVFoundation.h>
#import <assert.h>

const uint32_t CONST_BUFFER_SIZE = 0x10000;
const uint32_t CONST_UNIT_SIZE = 2048;

#define INPUT_BUS 1
#define OUTPUT_BUS 0

@implementation AACPlayer
{
    AudioFileID audioFileID; // An opaque data type that represents an audio file object.
    AudioStreamBasicDescription audioStreamBasicDescrpition; // An audio data format specification for a stream of audio
    AudioStreamPacketDescription *audioStreamPacketDescrption;
    
    
    SInt64 readedPacket; //参数类型
    UInt64 packetNums;
    
    AudioUnit audioUnit;
    AudioBufferList *buffList;
    
    Byte    *totalBuffer;
    UInt32  samplePosition;
    UInt32  totalPoistion;
    
    BOOL isPlaying;
    
    
    AudioConverterRef audioConverter;
}


- (instancetype)init {
    self = [super init];
    [self customAudioConfig];
    
    return self;
}

- (void)customAudioConfig {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"abc" withExtension:@"aac"];
    
    OSStatus status = AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &audioFileID);
    if (status != noErr) {
        NSLog(@"打开文件失败 %@", url);
        return ;
    }
    uint32_t size = sizeof(audioStreamBasicDescrpition);
    status = AudioFileGetProperty(audioFileID, kAudioFilePropertyDataFormat, &size, &audioStreamBasicDescrpition); // Gets the value of an audio file property.
    NSAssert(status == noErr, @"error");
    
    size = sizeof(packetNums); //type is UInt32
    status = AudioFileGetProperty(audioFileID,
                               kAudioFilePropertyAudioDataPacketCount,
                               &size,
                               &packetNums);
    readedPacket = 0;
    
    audioStreamPacketDescrption = malloc(sizeof(AudioStreamPacketDescription) * packetNums);
    
    NSAssert(status == noErr, ([NSString stringWithFormat:@"error status %d", status]) );
    
    audioConverter = NULL;
}


- (void)play {
    [self startRecorder:nil];
}


- (double)getCurrentTime {
    Float64 timeInterval = (readedPacket * 1.0) / 1;
    return timeInterval;
}



- (void)initRemoteIO {
    [self initAudioSession];
    
    [self initAudioComponent];
    
    [self initBuffer];
    
    [self initAudioProperty];
    
    [self initFormat];
    
    
    [self initPlayCallback];
    OSStatus result = AudioUnitInitialize(audioUnit);
    NSLog(@"result %d", result);
}

- (void)initAudioSession {
    NSError *error;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
    
}

- (void)initBuffer {
    UInt32 flag = 0;
    AudioUnitSetProperty(audioUnit,
                         kAudioUnitProperty_ShouldAllocateBuffer,
                         kAudioUnitScope_Output,
                         INPUT_BUS,
                         &flag,
                         sizeof(flag));
    
    buffList = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    buffList->mNumberBuffers = 1;
    buffList->mBuffers[0].mNumberChannels = 1;
    buffList->mBuffers[0].mDataByteSize = CONST_BUFFER_SIZE;
    buffList->mBuffers[0].mData = malloc(CONST_BUFFER_SIZE);
}

- (void)initAudioComponent {
    AudioComponentDescription audioDesc;
    audioDesc.componentType = kAudioUnitType_Output;
    audioDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    audioDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioDesc.componentFlags = 0;
    audioDesc.componentFlagsMask = 0;
    
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &audioDesc);
    AudioComponentInstanceNew(inputComponent, &audioUnit);
}

- (void)initFormat {
    AudioStreamBasicDescription audioFormat = audioStreamBasicDescrpition;
    
    if (audioFormat.mFormatID == kAudioFormatMPEGLayer3) {
        NSLog(@"ok");
    }
    UInt32 outDataSize;
    Boolean outWritable;
    AudioUnitGetPropertyInfo(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, INPUT_BUS, &outDataSize, &outWritable);
    NSLog(@"size:%d, able:%d", (unsigned int)outDataSize, outWritable);
    
    AudioStreamBasicDescription outputFormat;
    memset(&outputFormat, 0, sizeof(outputFormat));
    outputFormat.mSampleRate       = 44100;
    outputFormat.mFormatID         = kAudioFormatLinearPCM;
    outputFormat.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger;
    outputFormat.mBytesPerPacket   = 2;
    outputFormat.mFramesPerPacket  = 1;
    outputFormat.mBytesPerFrame    = 2;
    outputFormat.mChannelsPerFrame = 1;
    outputFormat.mBitsPerChannel   = 16;
    
    
    OSStatus status = 0;

    
    if (status != noErr) {
        NSLog(@"AudioUnitGetProperty error, ret: %d", (int)status);
    }
    
//    status = AudioUnitSetProperty(audioUnit,
//                         kAudioUnitProperty_StreamFormat,
//                         kAudioUnitScope_Input,
//                         INPUT_BUS,
//                         &audioFormat,
//                         sizeof(audioFormat));
    
//    AudioClassDescription *description = [self
//                                          getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC
//                                          fromManufacturer:kAppleSoftwareAudioCodecManufacturer]; //软编
    status = AudioConverterNew(&audioFormat, &outputFormat, &audioConverter);
    
    UInt32 oldBitRate = 0;
    UInt32 size = sizeof(oldBitRate);
    status = AudioConverterGetProperty(audioConverter, kAudioConverterEncodeBitRate, &size, &oldBitRate);
    
   status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  OUTPUT_BUS,
                                  &outputFormat,
                                  sizeof(outputFormat));
    
    NSAssert(!status, @"设置属性失败");
    
    if (status != noErr) {
        NSLog(@"AudioUnitGetProperty error, ret: %d", status);
    }
}

/**
 *  A callback function that supplies audio data to convert. This callback is invoked repeatedly as the converter is ready for new input data.
 
 */
OSStatus lyInInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AACPlayer *player = (__bridge AACPlayer *)(inUserData);
    UInt32 requestedPackets = *ioNumberDataPackets, bytes = 0;
    Byte *buffer = malloc(2048);
    AudioStreamPacketDescription *tmpPacketDescription = malloc(sizeof(AudioStreamPacketDescription));
    OSStatus status = AudioFileReadPackets(player->audioFileID, NO, &bytes, tmpPacketDescription, player->readedPacket, ioNumberDataPackets, buffer); // Reads packets of audio data from an audio file.
    *outDataPacketDescription = tmpPacketDescription;
    
    if(status) {
        NSLog(@"读取文件失败");
    };
    
    if (ioNumberDataPackets > 0) {
        ioData->mBuffers[0].mDataByteSize = bytes;
        ioData->mBuffers[0].mData = buffer;
        player->readedPacket += *ioNumberDataPackets;
    }
    
    if (*ioNumberDataPackets < requestedPackets) {
        //PCM 缓冲区还没满
        *ioNumberDataPackets = 0;
        return -1;
    }
    *ioNumberDataPackets = 1;
    return noErr;
}

static OSStatus PlayCallback(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData) {
    AACPlayer *player = (__bridge AACPlayer *)inRefCon;
    AudioStreamPacketDescription outPacketDescription = {0};
    OSStatus status = AudioConverterFillComplexBuffer(player->audioConverter, lyInInputDataProc, inRefCon, &inNumberFrames, player->buffList, &outPacketDescription);
    
    if (status) {
        NSLog(@"转换格式失败 %d", status);
    }
    
    NSLog(@"out size: %d", player->buffList->mBuffers[0].mDataByteSize);
    memcpy(ioData->mBuffers[0].mData, player->buffList->mBuffers[0].mData, player->buffList->mBuffers[0].mDataByteSize);
    ioData->mBuffers[0].mDataByteSize = player->buffList->mBuffers[0].mDataByteSize;

    //    OSStatus status = AudioUnitRender(player->audioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, player->buffList);
//    if (status) {
//        NSLog(@"status %d", status);
//    }
    
    if (player->buffList->mBuffers[0].mDataByteSize <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [player stopRecorder:nil];
        });
        
    }
    return noErr;
}

/**
 *  获取编解码器
 *
 *  @param type         编码格式
 *  @param manufacturer 软/硬编
 *
 编解码器（codec）指的是一个能够对一个信号或者一个数据流进行变换的设备或者程序。这里指的变换既包括将 信号或者数据流进行编码（通常是为了传输、存储或者加密）或者提取得到一个编码流的操作，也包括为了观察或者处理从这个编码流中恢复适合观察或操作的形式的操作。编解码器经常用在视频会议和流媒体等应用中。
 *  @return 指定编码器
 */
- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type
                                           fromManufacturer:(UInt32)manufacturer
{
    static AudioClassDescription desc;
    
    UInt32 encoderSpecifier = type;
    OSStatus st;
    
    UInt32 size;
    st = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                    sizeof(encoderSpecifier),
                                    &encoderSpecifier,
                                    &size);
    if (st) {
        NSLog(@"error getting audio format propery info: %d", (int)(st));
        return nil;
    }
    
    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    st = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                                sizeof(encoderSpecifier),
                                &encoderSpecifier,
                                &size,
                                descriptions);
    if (st) {
        NSLog(@"error getting audio format propery: %d", (int)(st));
        return nil;
    }
    
    for (unsigned int i = 0; i < count; i++) {
        if ((type == descriptions[i].mSubType) &&
            (manufacturer == descriptions[i].mManufacturer)) {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return &desc;
        }
    }
    
    return nil;
}



- (void)initPlayCallback {
    AURenderCallbackStruct playCallback;
    playCallback.inputProc = PlayCallback;
    playCallback.inputProcRefCon = (__bridge void *)self;
    AudioUnitSetProperty(audioUnit,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Input,
                         OUTPUT_BUS,
                         &playCallback,
                         sizeof(playCallback));
}

- (void)initAudioProperty {
    UInt32 flag = 0;
    OSStatus status = 0;
    if (flag) {
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input,
                                      INPUT_BUS,
                                      &flag,
                                      sizeof(flag));
    }
    
    flag = 1;
    if (flag) {
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output,
                                      OUTPUT_BUS,
                                      &flag,
                                      sizeof(flag));
    }
    
    
    NSLog(@"status %d", status);
    
}

#pragma mark - callback function



#pragma mark - public methods

- (void)startRecorder:(id)sender {
    isPlaying = YES;
    [ self initRemoteIO];
    AudioOutputUnitStart(audioUnit);
}

- (void)stopRecorder:(id)sender {
    if (!isPlaying) {
        return ;
    }
    isPlaying = NO;
    AudioOutputUnitStop(audioUnit);
    [self audio_release];
}

- (void)writePCMData:(Byte *)buffer size:(int)size {
    static FILE *file = NULL;
    NSString *path = [NSTemporaryDirectory() stringByAppendingString:@"/test.pcm"];
    if (!file) {
        file = fopen(path.UTF8String, "w");
    }
    fwrite(buffer, size, 1, file);
}

#pragma mark - private

- (void)audio_release {
    AudioUnitUninitialize(audioUnit);
    if (buffList != NULL) {
        free(buffList);
        buffList = NULL;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    AudioOutputUnitStop(audioUnit);
    AudioComponentInstanceDispose(audioUnit);
    if (buffList != NULL) {
        free(buffList);
        buffList = NULL;
    }
    AudioUnitUninitialize(audioUnit);
    
    AudioConverterDispose(audioConverter);
}


@end
