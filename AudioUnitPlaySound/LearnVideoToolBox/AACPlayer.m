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

const uint32_t CONST_BUFFER_SIZE = 0x10000;
const uint32_t CONST_UNIT_SIZE = 2048;

#define INPUT_BUS 1
#define OUTPUT_BUS 0

@implementation AACPlayer
{
    AudioFileID audioFileID; // An opaque data type that represents an audio file object.
    AudioStreamBasicDescription audioStreamBasicDescrpition; // An audio data format specification for a stream of audio
    
    SInt64 readedPacket; //参数类型
    UInt64 packetNums;
    
    AudioUnit audioUnit;
    AudioBufferList *buffList;
    
    Byte    *totalBuffer;
    UInt32  samplePosition;
    UInt32  totalPoistion;
    
    BOOL isPlaying;
}


- (instancetype)init {
    self = [super init];
    [self customAudioConfig];
    
    return self;
}

- (void)customAudioConfig {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"abc" withExtension:@"aac"];
    
//    AudioFileCreateWithURL((__bridge CFURLRef)ur, kAudioFileMP3Type, <#const AudioStreamBasicDescription * _Nonnull inFormat#>, <#AudioFileFlags inFlags#>, <#AudioFileID  _Nullable * _Nonnull outAudioFile#>)
    OSStatus status = AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &audioFileID);
//    OSStatus status = AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &audioFileID); //Open an existing audio file specified by a URL.
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
    
    uint32_t bytes = 0, packets = (uint32_t)packetNums + 1;
    totalBuffer = malloc(sizeof(Byte) * 20 * 1024 * 1024);
    status = AudioFileReadPackets(audioFileID, NO, &bytes, NULL, 0, &packets, totalBuffer); // Reads packets of audio data from an audio file.
    samplePosition = 0;
    totalPoistion = bytes;
    
    NSAssert(status == noErr, ([NSString stringWithFormat:@"error status %d", status]) );
}


- (void)play {
    [self startRecorder:nil];
}


- (void)fillBuffer {
    if (samplePosition + CONST_UNIT_SIZE > totalPoistion) {
        buffList->mBuffers[0].mDataByteSize = totalPoistion - samplePosition;
    }
    else {
        buffList->mBuffers[0].mDataByteSize = CONST_UNIT_SIZE;
    }
    memcpy(buffList->mBuffers[0].mData, totalBuffer + samplePosition, buffList->mBuffers[0].mDataByteSize);
    samplePosition += buffList->mBuffers[0].mDataByteSize;
}



- (double)getCurrentTime {
    Float64 timeInterval = (readedPacket * 1.0) / 1;
    return timeInterval;
}



- (void)initRemoteIO {
    [self initAudioSession];
    
    [self initBuffer];
    
    [self initAudioComponent];
    
    [self initFormat];
    
    [self initAudioProperty];
    
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
    buffList->mBuffers[0].mDataByteSize = CONST_BUFFER_SIZE * sizeof(short);
    buffList->mBuffers[0].mData = malloc(sizeof(short) * 2048);
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
//    audioFormat.mSampleRate = 44100;
//    audioFormat.mFormatID = kAudioFormatLinearPCM;
//    audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
//    audioFormat.mFramesPerPacket = 1;
//    audioFormat.mChannelsPerFrame = 1;
//    audioFormat.mBitsPerChannel = 16;
//    audioFormat.mBytesPerPacket = 2;
//    audioFormat.mBytesPerFrame = 2;
    
    UInt32 outDataSize;
    Boolean outWritable;
    AudioUnitGetPropertyInfo(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, INPUT_BUS, &outDataSize, &outWritable);
    NSLog(@"size:%d, able:%d", outDataSize, outWritable);
    
    AudioStreamBasicDescription outputFormat;
    OSStatus status;
    UInt32 outputSize = sizeof(outputFormat);
    status =  AudioUnitGetProperty(audioUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Input,
                                   OUTPUT_BUS,
                                   &outputFormat,
                                   &outputSize);
    if (status != noErr) {
        NSLog(@"AudioUnitGetProperty error, ret: %d", status);
    }
    
    AudioUnitSetProperty(audioUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Output,
                         INPUT_BUS,
                         &audioFormat,
                         sizeof(audioFormat));
    
    AudioUnitSetProperty(audioUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         OUTPUT_BUS,
                         &audioFormat,
                         sizeof(audioFormat));
    
    // after set
    status =  AudioUnitGetProperty(audioUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Input,
                                   OUTPUT_BUS,
                                   &outputFormat,
                                   &outputSize);
    if (status != noErr) {
        NSLog(@"AudioUnitGetProperty error, ret: %d", status);
    }
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
    UInt32 flag = 1;
    
    AudioUnitSetProperty(audioUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Input,
                         INPUT_BUS,
                         &flag,
                         sizeof(flag));
    
    AudioUnitSetProperty(audioUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Input,
                         OUTPUT_BUS,
                         &flag,
                         sizeof(flag));
    
}

#pragma mark - callback function


static OSStatus PlayCallback(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData) {
    AACPlayer *player = (__bridge AACPlayer *)inRefCon;
    [player fillBuffer];
    memcpy(ioData->mBuffers[0].mData, player->buffList->mBuffers[0].mData, player->buffList->mBuffers[0].mDataByteSize);
    NSLog(@"out size: %d", player->buffList->mBuffers[0].mDataByteSize);
    AudioUnitRender(player->audioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, player->buffList);
    
    if (player->buffList->mBuffers[0].mDataByteSize <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [player stopRecorder:nil];
        });
        
    }
    return noErr;
}

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
    //    [[NSNotificationCenter defaultCenter] removeObserver:self];
    //    AudioOutputUnitStop(audioUnit);
    //    AudioComponentInstanceDispose(audioUnit);
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
}


@end
