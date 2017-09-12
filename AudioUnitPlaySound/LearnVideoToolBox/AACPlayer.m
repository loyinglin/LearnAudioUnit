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
    AudioStreamBasicDescription audioFileFormat; // An audio data format specification for a stream of audio
    AudioStreamPacketDescription *audioPacketFormat;
    
    
    SInt64 readedPacket; //参数类型
    UInt64 packetNums;
    
    AudioUnit audioUnit;
    AudioBufferList *buffList;
    Byte *convertBuffer;
    
    
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
    if (status) {
        NSLog(@"打开文件失败 %@", url);
    }
    uint32_t size = sizeof(AudioStreamBasicDescription);
    status = AudioFileGetProperty(audioFileID, kAudioFilePropertyDataFormat, &size, &audioFileFormat); // Gets the value of an audio file property.
    NSAssert(status == noErr, ([NSString stringWithFormat:@"error status %d", status]) );
    
    size = sizeof(packetNums); //type is UInt32
    status = AudioFileGetProperty(audioFileID,
                               kAudioFilePropertyAudioDataPacketCount,
                               &size,
                               &packetNums);
    readedPacket = 0;
    
    audioPacketFormat = malloc(sizeof(AudioStreamPacketDescription) * packetNums);
    NSAssert(status == noErr, ([NSString stringWithFormat:@"error status %d", status]) );
    
    audioConverter = NULL;
}


- (void)play {
    isPlaying = YES;
    
    [ self initRemoteIO];
    AudioOutputUnitStart(audioUnit);
}


- (double)getCurrentTime {
    Float64 timeInterval = (readedPacket * 1.0) / 1;
    return timeInterval;
}



- (void)initRemoteIO {
    NSError *error = nil;
    OSStatus status = noErr;
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
    
    
    
    AudioComponentDescription audioDesc;
    audioDesc.componentType = kAudioUnitType_Output;
    audioDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    audioDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioDesc.componentFlags = 0;
    audioDesc.componentFlagsMask = 0;
    
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &audioDesc);
    AudioComponentInstanceNew(inputComponent, &audioUnit);

    // BUFFER
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
    
    
    convertBuffer = malloc(CONST_BUFFER_SIZE);
    
    
    //initAudioProperty
    
    flag = 1;
    if (flag) {
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output,
                                      OUTPUT_BUS,
                                      &flag,
                                      sizeof(flag));
    }
    if (status) {
        NSLog(@"AudioUnitSetProperty error with status:%d", status);
    }
    
    
    //initFormat
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
    
    
//    AudioStreamBasicDescription audioFormat = {0}; // 初始化输出流的结构体描述为0. 很重要。
//    audioFormat.mSampleRate = 44100; // 音频流，在正常播放情况下的帧率。如果是压缩的格式，这个属性表示解压缩后的帧率。帧率不能为0。
//    audioFormat.mFormatID = kAudioFormatMPEG4AAC; // 设置编码格式
//    audioFormat.mFormatFlags = kMPEG4Object_AAC_LC; // 无损编码 ，0表示没有
//    audioFormat.mBytesPerPacket = 0; // 每一个packet的音频数据大小。如果的动态大小，设置为0。动态大小的格式，需要用AudioStreamPacketDescription 来确定每个packet的大小。
//    audioFormat.mFramesPerPacket = 1024; // 每个packet的帧数。如果是未压缩的音频数据，值是1。动态码率格式，这个值是一个较大的固定数字，比如说AAC的1024。如果是动态大小帧数（比如Ogg格式）设置为0。
//    audioFormat.mBytesPerFrame = 0; //  每帧的大小。每一帧的起始点到下一帧的起始点。如果是压缩格式，设置为0 。
//    audioFormat.mChannelsPerFrame = 1; // 声道数
//    audioFormat.mBitsPerChannel = 0; // 压缩格式设置为0
//    audioFormat.mReserved = 0; // 8字节对齐，填0.
    
    [self printAudioStreamBasicDescription:audioFileFormat];
    [self printAudioStreamBasicDescription:outputFormat];
    status = AudioConverterNew(&audioFileFormat, &outputFormat, &audioConverter);
    if (status) {
        NSLog(@"AudioConverterNew eror with status:%d", status);
    }
    
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  OUTPUT_BUS,
                                  &outputFormat,
                                  sizeof(outputFormat));
    if (status) {
        NSLog(@"AudioUnitSetProperty eror with status:%d", status);
    }
    
    
    [self initPlayCallback];
    
    
    OSStatus result = AudioUnitInitialize(audioUnit);
    NSLog(@"result %d", result);
}

/**
 *  A callback function that supplies audio data to convert. This callback is invoked repeatedly as the converter is ready for new input data.
 
 */
OSStatus lyInInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AACPlayer *player = (__bridge AACPlayer *)(inUserData);
    
    
    if (*ioNumberDataPackets != 1) {
        NSLog(@"sdfas");
    }
    
    UInt32 byteSize = CONST_BUFFER_SIZE;

    OSStatus status = AudioFileReadPacketData(player->audioFileID, NO, &byteSize, player->audioPacketFormat, player->readedPacket, ioNumberDataPackets, player->convertBuffer); // Reads packets of audio data from an audio file.
    
    if (outDataPacketDescription) {
        *outDataPacketDescription = player->audioPacketFormat;
    }
    
    
    if(status) {
        NSLog(@"读取文件失败");
    }
    
    if (!status && ioNumberDataPackets > 0) {
        ioData->mBuffers[0].mDataByteSize = byteSize;
        ioData->mBuffers[0].mData = player->convertBuffer;
        player->readedPacket += *ioNumberDataPackets;
        return noErr;
    }
    else {
        return -12306; // NoMoreData
    }
    
}

static OSStatus PlayCallback(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData) {
    AACPlayer *player = (__bridge AACPlayer *)inRefCon;
//    AudioStreamPacketDescription packetFormat = {0};
    AudioStreamPacketDescription outPacketDescription;
    memset(&outPacketDescription, 0, sizeof(AudioStreamPacketDescription));
    outPacketDescription.mDataByteSize = 128;
    outPacketDescription.mStartOffset = 0;
    outPacketDescription.mVariableFramesInPacket = 0;

    player->buffList->mBuffers[0].mDataByteSize = CONST_BUFFER_SIZE;
    OSStatus status = AudioConverterFillComplexBuffer(player->audioConverter, lyInInputDataProc, inRefCon, &inNumberFrames, player->buffList, NULL);
    
    if (status) {
        NSLog(@"转换格式失败 %d", status);
    }
    
    NSLog(@"out size: %d", player->buffList->mBuffers[0].mDataByteSize);
    memcpy(ioData->mBuffers[0].mData, player->buffList->mBuffers[0].mData, player->buffList->mBuffers[0].mDataByteSize);
    ioData->mBuffers[0].mDataByteSize = player->buffList->mBuffers[0].mDataByteSize;
    
    fwrite(player->buffList->mBuffers[0].mData, player->buffList->mBuffers[0].mDataByteSize, 1, [player pcmFile]);
    
    if (player->buffList->mBuffers[0].mDataByteSize <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [player stop];
        });
        
    }
    return noErr;
}







- (FILE *)pcmFile {
    static FILE *_pcmFile;
    if (!_pcmFile) {
        NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test.pcm"];
        _pcmFile = fopen(filePath.UTF8String, "w");
        
    }
    return _pcmFile;
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


- (void)stop {
    if (!isPlaying) {
        return ;
    }
    isPlaying = NO;
    AudioOutputUnitStop(audioUnit);
    [self audio_release];
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


- (void)printAudioStreamBasicDescription:(AudioStreamBasicDescription)asbd {
    char formatID[5];
    UInt32 mFormatID = CFSwapInt32HostToBig(asbd.mFormatID);
    bcopy (&mFormatID, formatID, 4);
    formatID[4] = '\0';
    printf("Sample Rate:         %10.0f\n",  asbd.mSampleRate);
    printf("Format ID:           %10s\n",    formatID);
    printf("Format Flags:        %10X\n",    (unsigned int)asbd.mFormatFlags);
    printf("Bytes per Packet:    %10d\n",    (unsigned int)asbd.mBytesPerPacket);
    printf("Frames per Packet:   %10d\n",    (unsigned int)asbd.mFramesPerPacket);
    printf("Bytes per Frame:     %10d\n",    (unsigned int)asbd.mBytesPerFrame);
    printf("Channels per Frame:  %10d\n",    (unsigned int)asbd.mChannelsPerFrame);
    printf("Bits per Channel:    %10d\n",    (unsigned int)asbd.mBitsPerChannel);
    printf("\n");
}
@end
