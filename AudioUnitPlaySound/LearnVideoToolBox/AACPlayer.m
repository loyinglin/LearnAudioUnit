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
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"abc" withExtension:@"mp3"];
    
    OSStatus status = AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &audioFileID);
    if (status != noErr) {
        NSLog(@"打开文件失败 %@", url);
        return ;
    }
    uint32_t size = sizeof(AudioStreamBasicDescription);
    status = AudioFileGetProperty(audioFileID, kAudioFilePropertyDataFormat, &size, &audioFileFormat); // Gets the value of an audio file property.
    NSAssert(status == noErr, @"error");
    
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
    UInt32 bytes = 0;
    OSStatus status = AudioFileReadPackets(player->audioFileID, NO, &bytes, player->audioPacketFormat, player->readedPacket, ioNumberDataPackets, player->buffList->mBuffers[0].mData); // Reads packets of audio data from an audio file.
    *outDataPacketDescription = player->audioPacketFormat;
    
    if(status) {
        NSLog(@"读取文件失败");
    };
    
    if (ioNumberDataPackets > 0) {
        ioData->mBuffers[0].mDataByteSize = bytes;
        ioData->mBuffers[0].mData = player->buffList->mBuffers[0].mData;
        player->readedPacket += *ioNumberDataPackets;
    }
    
    return noErr;
}

static OSStatus PlayCallback(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData) {
    AACPlayer *player = (__bridge AACPlayer *)inRefCon;
    OSStatus status = AudioConverterFillComplexBuffer(player->audioConverter, lyInInputDataProc, inRefCon, &inNumberFrames, player->buffList, NULL);
    
    if (status) {
        NSLog(@"转换格式失败 %d", status);
    }
    
    NSLog(@"out size: %d", player->buffList->mBuffers[0].mDataByteSize);
    memcpy(ioData->mBuffers[0].mData, player->buffList->mBuffers[0].mData, player->buffList->mBuffers[0].mDataByteSize);
    ioData->mBuffers[0].mDataByteSize = player->buffList->mBuffers[0].mDataByteSize;

    
    if (player->buffList->mBuffers[0].mDataByteSize <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [player stop];
        });
        
    }
    return noErr;
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


@end
