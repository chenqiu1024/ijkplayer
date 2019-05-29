/*
 * IJKSDLAudioUnitController.m
 *
 * Copyright (c) 2013 Bilibili
 * Copyright (c) 2013 Zhang Rui <bbcallen@gmail.com>
 *
 * based on https://github.com/kolyvan/kxmovie
 *
 * This file is part of ijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * ijkPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with ijkPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#import "IJKSDLAudioUnitController.h"
#import "IJKSDLAudioKit.h"
#include "ijksdl/ijksdl_log.h"
#import "ijksdl/C2Buffer.h"

#import <AVFoundation/AVFoundation.h>

//const int BuffersCount = 1;
//const int BufferSize = 1024 * 2 * sizeof(SInt16) * 16;

@interface IJKSDLAudioUnitController () <C2BufferDelegate>

@property (nonatomic, assign) AudioUnit ioUnit;
//@property (nonatomic, assign) AudioUnit resampleUnit;
@property (nonatomic, assign) AudioUnit mixerUnit;

@property (nonatomic, assign) AudioBufferList* audioBufferList;
@property (nonatomic, copy) NSArray<C2Buffer* >* c2Buffers;

@end

@implementation IJKSDLAudioUnitController {
    AUGraph _auGraph;
    BOOL _isPaused;
}

- (id)initWithAudioSpec:(const SDL_AudioSpec *)aSpec
{NSLog(@"#AudioDeadlock# init . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    self = [super init];
    if (self) {
        if (aSpec == NULL) {
            self = nil;
            return nil;
        }
        _spec = *aSpec;

        if (aSpec->format != AUDIO_S16SYS) {
            NSLog(@"aout_open_audio: unsupported format %d\n", (int)aSpec->format);
            return nil;
        }

        if (aSpec->channels > 6) {
            NSLog(@"aout_open_audio: unsupported channels %d\n", (int)aSpec->channels);
            return nil;
        }

        _audioBufferList = (AudioBufferList*) malloc(sizeof(AudioBufferList));
        _audioBufferList->mNumberBuffers = 1;
        NSMutableArray* c2Buffers = [[NSMutableArray alloc] init];
        for (int i=0; i<_audioBufferList->mNumberBuffers; ++i)
        {
            _audioBufferList->mBuffers[i].mNumberChannels = 2;
            _audioBufferList->mBuffers[i].mDataByteSize = 4096;
            _audioBufferList->mBuffers[i].mData = malloc(4096);
            
            C2Buffer* c2Buffer = [[C2Buffer alloc] initWithSize:65536 delegate:self];
            [c2Buffer notifyConsumerWillDeactive:1];///!!!For Debug
            [c2Buffers addObject:c2Buffer];
        }
        _c2Buffers = [NSArray arrayWithArray:c2Buffers];
        
        OSStatus status;
        
        NewAUGraph(&_auGraph);;
        
        AUNode ioNode, mixerNode;//, resampleNode;
        AudioComponentDescription ioACDesc, mixerACDesc;//, resampleACDesc, spliterACDesc;
        
//        IJKSDLGetAudioComponentDescriptionFromSpec(&_spec, &mixerACDesc);
        mixerACDesc.componentType = kAudioUnitType_Mixer;
        mixerACDesc.componentSubType = kAudioUnitSubType_MultiChannelMixer;
        mixerACDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
        mixerACDesc.componentFlags = 0;
        mixerACDesc.componentFlagsMask = 0;
        
        IJKSDLGetAudioComponentDescriptionFromSpec(&_spec, &ioACDesc);

//        resampleACDesc.componentType = kAudioUnitType_FormatConverter;
//        resampleACDesc.componentSubType = kAudioUnitSubType_AUConverter;
//        resampleACDesc.componentFlags = 0;
//        resampleACDesc.componentFlagsMask = 0;
//        resampleACDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
        
        AUGraphAddNode(_auGraph, &ioACDesc, &ioNode);
//        AUGraphAddNode(_auGraph, &resampleACDesc, &resampleNode);
        AUGraphAddNode(_auGraph, &mixerACDesc, &mixerNode);
        AUGraphConnectNodeInput(_auGraph, ioNode, 1, mixerNode, 1);
        //AUGraphConnectNodeInput(_auGraph, resampleNode, 0, mixerNode, 0);
        AUGraphConnectNodeInput(_auGraph, mixerNode, 0, ioNode, 0);
        NSLog(@"#AUGraph# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
        
        status = AUGraphOpen(_auGraph);
        NSLog(@"#AUGraph# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
        
        AUGraphNodeInfo(_auGraph, ioNode, NULL, &_ioUnit);
        status = AUGraphNodeInfo(_auGraph, mixerNode, NULL, &_mixerUnit);
//        AUGraphNodeInfo(_auGraph, resampleNode, NULL, &_resampleUnit);
        NSLog(@"#AUGraph# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
        
        UInt32 flag = 1;
        status = AudioUnitSetProperty(_ioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input,
                                      1,
                                      &flag,
                                      sizeof(flag));
        status = AudioUnitSetProperty(_ioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output,
                                      0,
                                      &flag,
                                      sizeof(flag));
        NSLog(@"#AUGraph# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
        
        UInt32 busCount = 2;
        status = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &busCount, sizeof(busCount));
        
        UInt32 maximumFramesPerSlice = 4096;
        status = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFramesPerSlice, sizeof(maximumFramesPerSlice));

        /* Set the desired format */
        UInt32 sizeOfASBD = sizeof(AudioStreamBasicDescription);
        /* Get the current format */
        _spec.format = AUDIO_S16SYS;
        _spec.channels = 2;
        AudioStreamBasicDescription mediaASBD;
        IJKSDLGetAudioStreamBasicDescriptionFromSpec(&_spec, &mediaASBD);
        
//        status = AudioUnitSetProperty(_resampleUnit,
//                                      kAudioUnitProperty_StreamFormat,
//                                      kAudioUnitScope_Input,
//                                      0,
//                                      &mediaASBD,
//                                      sizeOfASBD);
        
        double preferredHardwareInputSampleRate = 16000.f;
        if ([[AVAudioSession sharedInstance] respondsToSelector:@selector(sampleRate)])
        {
            preferredHardwareInputSampleRate = [[AVAudioSession sharedInstance] sampleRate];
        }
        else
        {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            preferredHardwareInputSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
#pragma clang diagnostic pop
        }
        
        AudioStreamBasicDescription ioInputASBD = mediaASBD;
        ioInputASBD.mSampleRate = preferredHardwareInputSampleRate;
        ioInputASBD.mFormatID = kAudioFormatLinearPCM;
        // kAudioFormatFlagIsNonInterleaved will create 1 AudioBuffer for each channel, while kAudioFormatFlagIsPacked will create 1 interleaved AudioBuffer for all 2 channels:
        ioInputASBD.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        ioInputASBD.mFramesPerPacket = 1;
        ioInputASBD.mChannelsPerFrame = 1;
        ioInputASBD.mBitsPerChannel = 16;
        ioInputASBD.mBytesPerFrame = ioInputASBD.mBitsPerChannel * ioInputASBD.mChannelsPerFrame / 8;
        ioInputASBD.mBytesPerPacket = ioInputASBD.mBytesPerFrame * ioInputASBD.mFramesPerPacket;
        
        AudioStreamBasicDescription ioOutputASBD = mediaASBD;
        ioOutputASBD.mChannelsPerFrame = 2;
        ioOutputASBD.mBytesPerFrame = ioOutputASBD.mBitsPerChannel * ioOutputASBD.mChannelsPerFrame / 8;
        ioOutputASBD.mBytesPerPacket = ioOutputASBD.mBytesPerFrame * ioOutputASBD.mFramesPerPacket;
        
//        status = AudioUnitSetProperty(_resampleUnit,
//                                      kAudioUnitProperty_StreamFormat,
//                                      kAudioUnitScope_Output,
//                                      0,
//                                      &ioOutASBD,
//                                      sizeOfASBD);

        status = AudioUnitSetProperty(_ioUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output,
                                      1,
                                      &ioInputASBD,
                                      sizeOfASBD);
        
        status = AudioUnitSetProperty(_mixerUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      1,
                                      &mediaASBD,
                                      sizeOfASBD);

        status = AudioUnitSetProperty(_ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &ioOutputASBD, sizeOfASBD);
        NSLog(@"#AUGraph# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
        
        AURenderCallbackStruct renderAudioSourceCallback;
        renderAudioSourceCallback.inputProc = (AURenderCallback) RenderCallback;
        renderAudioSourceCallback.inputProcRefCon = (__bridge void*) self;
        status = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 1, &renderAudioSourceCallback, sizeof(renderAudioSourceCallback));
        NSLog(@"#AUGraph#AudioUnitCallback# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
        
//        AURenderCallbackStruct micInputCallback;
//        micInputCallback.inputProc = (AURenderCallback) MicInputCallback;
//        micInputCallback.inputProcRefCon = (__bridge void*) self;
//        status = AudioUnitSetProperty(_ioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &micInputCallback, sizeof(micInputCallback));
//        status = AudioUnitAddRenderNotify(_inputIOUnit, (AURenderCallback)MicInputCallback, (__bridge void*)self);
//        NSLog(@"#AUGraph#AudioUnitCallback# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
        
//        AURenderCallbackStruct mixerRenderNotifyCallback;
//        mixerRenderNotifyCallback.inputProc = (AURenderCallback) MixerRenderNotifyCallback;
//        mixerRenderNotifyCallback.inputProcRefCon = (__bridge void*) self;
        status = AudioUnitAddRenderNotify(_mixerUnit, (AURenderCallback)MixerRenderNotifyCallback, (__bridge void*)self);
        NSLog(@"#AUGraph#AudioUnitCallback# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
        
//        AURenderCallbackStruct outputRenderCallback;
//        outputRenderCallback.inputProc = (AURenderCallback) OutputRenderCallback;
//        outputRenderCallback.inputProcRefCon = (__bridge void*) self;
//        status = AudioUnitSetProperty(_outputIOUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &outputRenderCallback, sizeof(outputRenderCallback));
//        NSLog(@"#AUGraph#AudioUnitCallback# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
        
        SDL_CalculateAudioSpec(&_spec);
        
        status = AUGraphInitialize(_auGraph);
        NSLog(@"#AUGraph#AudioUnitCallback# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
        CAShow(_auGraph);
    }
    return self;
}

- (void)dealloc
{NSLog(@"#AUGraph# dealloc . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    [self close];
}

- (void)play
{NSLog(@"#AUGraph# play . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    if (!_auGraph)
        return;

    _isPaused = NO;
    NSError *error = nil;
    if (NO == [[AVAudioSession sharedInstance] setActive:YES error:&error]) {
        NSLog(@"#AUGraph#: AVAudioSession.setActive(YES) failed: %@\n", error ? [error localizedDescription] : @"nil");
    }

    OSStatus status = AUGraphStart(_auGraph);
    NSLog(@"#AUGraph# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
}

- (void)pause
{NSLog(@"#AUGraph# pause . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    if (!_auGraph)
        return;

    _isPaused = YES;
    OSStatus status = AUGraphStop(_auGraph);
    if (status != noErr)
        ALOGE("#AUGraph#: failed to stop AudioUnit (%d)\n", (int)status);
}

- (void)flush
{NSLog(@"#AUGraph# flush . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    if (!_auGraph)
        return;

///!!!    AudioUnitReset(_auUnit, kAudioUnitScope_Global, 0);
//    for (C2Buffer* c2buffer in _c2Buffers)
//    {
//        [c2buffer finish];
//    }
}

- (void)stop
{NSLog(@"#AUGraph# stop . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    if (!_auGraph)
        return;

//    for (C2Buffer* c2buffer in _c2Buffers)
//    {
//        [c2buffer finish];
//    }
    
    OSStatus status = AUGraphStop(_auGraph);
    if (status != noErr)
        ALOGE("#AUGraph#: failed to stop AudioUnit (%d)", (int)status);
}

- (void)close
{NSLog(@"#AudioDeadlock# close . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    [self stop];

    if (!_auGraph)
        return;

//    AURenderCallbackStruct callback;
//    memset(&callback, 0, sizeof(AURenderCallbackStruct));
//    AudioUnitSetProperty(_auUnit,
//                         kAudioUnitProperty_SetRenderCallback,
//                         kAudioUnitScope_Input, 0, &callback,
//                         sizeof(callback));
//
//    AudioComponentInstanceDispose(_auUnit);
//    _auUnit = NULL;
    AUGraphClose(_auGraph);
    _auGraph = NULL;
    
    if (_audioBufferList)
    {
        for (int i=0; i<_audioBufferList->mNumberBuffers; ++i)
        {
            if (_audioBufferList->mBuffers[i].mData)
                free(_audioBufferList->mBuffers[i].mData);
        }
        free(_audioBufferList);
    }
    for (C2Buffer* c2buffer in _c2Buffers)
    {
        [c2buffer finish];
    }
}

- (void)setPlaybackRate:(float)playbackRate
{
//    if (fabsf(playbackRate - 1.0f) <= 0.000001) {
//        UInt32 propValue = 1;
//        AudioQueueSetProperty(_audioQueueRef, kAudioQueueProperty_TimePitchBypass, &propValue, sizeof(propValue));
//        AudioQueueSetParameter(_audioQueueRef, kAudioQueueParam_PlayRate, 1.0f);
//    } else {
//        UInt32 propValue = 0;
//        AudioQueueSetProperty(_audioQueueRef, kAudioQueueProperty_TimePitchBypass, &propValue, sizeof(propValue));
//        AudioQueueSetParameter(_audioQueueRef, kAudioQueueParam_PlayRate, playbackRate);
//    }
}

- (void)setPlaybackVolume:(float)playbackVolume
{
//    float aq_volume = playbackVolume;
//    if (fabsf(aq_volume - 1.0f) <= 0.000001) {
//        AudioQueueSetParameter(_audioQueueRef, kAudioQueueParam_Volume, 1.f);
//    } else {
//        AudioQueueSetParameter(_audioQueueRef, kAudioQueueParam_Volume, aq_volume);
//    }
}

- (double)get_latency_seconds
{
//    return ((double)(kIJKAudioQueueNumberBuffers)) * _spec.samples / _spec.freq;
    return ((double)(3)) * _spec.samples / _spec.freq;
}

#pragma mark C2BufferDelegate
-(size_t) c2BufferFillDataTo:(void*)buffer length:(size_t)length {
    _spec.callback(_spec.userdata, buffer, (int)length, _spec.audioParams);
    return length;
}

static OSStatus RenderCallback(void                        *inRefCon,
                               AudioUnitRenderActionFlags  *ioActionFlags,
                               const AudioTimeStamp        *inTimeStamp,
                               UInt32                      inBusNumber,
                               UInt32                      inNumberFrames,
                               AudioBufferList             *ioData)
{
    @autoreleasepool {
        NSLog(@"#AUGraph#AudioUnitCallback# RenderCallback : flag=0x%x, inBusNumber=%d, inNumberFrames=%d, ioData=0x%lx", *ioActionFlags, inBusNumber, inNumberFrames, (long)ioData);
        if (ioData)
        {
//            NSLog(@"#AUGraph#AudioUnitCallback# RenderCallback : numBuffers=%d", ioData->mNumberBuffers);
            for (int i=0; i<ioData->mNumberBuffers; ++i)
            {
                AudioBuffer audioBuffer = ioData->mBuffers[i];
//                NSLog(@"#AUGraph#AudioUnitCallback# RenderCallback : audioBuffer[%d].channels=%d, .size=%d, .data=0x%lx", i, audioBuffer.mNumberChannels, audioBuffer.mDataByteSize, (long)audioBuffer.mData);
            }
        }
        
        IJKSDLAudioUnitController* auController = (__bridge IJKSDLAudioUnitController *) inRefCon;

        if (!auController || auController->_isPaused) {
            *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
            for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
                AudioBuffer *ioBuffer = &ioData->mBuffers[i];
                memset(ioBuffer->mData, auController.spec.silence, ioBuffer->mDataByteSize);
            }
            return noErr;
        }

        for (int i = 0; i < (int)ioData->mNumberBuffers; i++) {
            AudioBuffer *ioBuffer = &ioData->mBuffers[i];
            [auController.c2Buffers[i] readBytesForConsumer:0 into:ioBuffer->mData length:ioBuffer->mDataByteSize isFinal:NO completion:nil];
        }
        //#AudioCallback#
        return noErr;
    }
}

static OSStatus OutputRenderCallback(void                        *inRefCon,
                               AudioUnitRenderActionFlags  *ioActionFlags,
                               const AudioTimeStamp        *inTimeStamp,
                               UInt32                      inBusNumber,
                               UInt32                      inNumberFrames,
                               AudioBufferList             *ioData)
{
    @autoreleasepool {
        NSLog(@"#AUGraph# OutputRenderCallback : flag=0x%x, inBusNumber=%d, inNumberFrames=%d, ioData=0x%lx", *ioActionFlags, inBusNumber, inNumberFrames, (long)ioData);
        if (ioData)
        {
//            NSLog(@"#AUGraph# OutputRenderCallback : numBuffers=%d", ioData->mNumberBuffers);
            IJKSDLAudioUnitController* auController = (__bridge IJKSDLAudioUnitController *) inRefCon;
            for (int i=0; i<ioData->mNumberBuffers; ++i)
            {
                AudioBuffer audioBuffer = ioData->mBuffers[i];
//                NSLog(@"#AUGraph# OutputRenderCallback : audioBuffer[%d].channels=%d, .size=%d, .data=0x%lx", i, audioBuffer.mNumberChannels, audioBuffer.mDataByteSize, (long)audioBuffer.mData);
                if (audioBuffer.mData)/// && (*ioActionFlags & kAudioUnitRenderAction_PostRender))
                {//PeriodInSamples = SampleRate / Frequency = 1024 / k, k = 1024 * Frequency / SampleRate
//                    const float F0 = 430.7, F1 = 861.4, A0 = 0.05, A1 = 0.05;
//                    static NSUInteger totalSamples = 0;
//                    ushort* pDst = (ushort*)audioBuffer.mData;
//                    for (int iSample=0; iSample<audioBuffer.mDataByteSize/4; ++iSample)
//                    {
//                        totalSamples++;
//                        float a0 = sinf(2 * M_PI * F0 * totalSamples / 44100.f) * A0;
//                        *(pDst++) = 32768 * a0 + 32767;
//                        float a1 = sinf(2 * M_PI * F1 * totalSamples / 44100.f) * A1;
//                        *(pDst++) = 32768 * a1 + 32767;
//                    }
                    
                    [auController.c2Buffers[i] readBytesForConsumer:1 into:audioBuffer.mData length:audioBuffer.mDataByteSize isFinal:NO completion:nil];
                }
            }
        }
        return noErr;
    }
}

static OSStatus MixerRenderNotifyCallback(void                        *inRefCon,
                               AudioUnitRenderActionFlags  *ioActionFlags,
                               const AudioTimeStamp        *inTimeStamp,
                               UInt32                      inBusNumber,
                               UInt32                      inNumberFrames,
                               AudioBufferList             *ioData)
{
    @autoreleasepool {
        IJKSDLAudioUnitController* auController = (__bridge IJKSDLAudioUnitController *) inRefCon;
        NSLog(@"#AUGraph# MixerRenderNotifyCallback : flag=0x%x, inBusNumber=%d, inNumberFrames=%d, ioData=0x%lx", *ioActionFlags, inBusNumber, inNumberFrames, (long)ioData);
        if (ioData)
        {
//            NSLog(@"#AUGraph# MixerRenderNotifyCallback : numBuffers=%d", ioData->mNumberBuffers);
            for (int i=0; i<ioData->mNumberBuffers; ++i)
            {
                AudioBuffer audioBuffer = ioData->mBuffers[i];
//                NSLog(@"#AUGraph# MixerRenderNotifyCallback : audioBuffer[%d].channels=%d, .size=%d, .data=0x%lx", i, audioBuffer.mNumberChannels, audioBuffer.mDataByteSize, (long)audioBuffer.mData);
                if (audioBuffer.mData && (*ioActionFlags & kAudioUnitRenderAction_PostRender))
                {//PeriodInSamples = SampleRate / Frequency = 1024 / k, k = 1024 * Frequency / SampleRate
//                    const float F0 = 430.7, F1 = 861.4, A0 = 0.05, A1 = 0.05;
//                    static NSUInteger totalSamples = 0;
//                    ushort* pDst = (ushort*)audioBuffer.mData;
//                    //for (int iSample=0; iSample<inNumberFrames; ++iSample)
//                    for (int iSample=0; iSample<audioBuffer.mDataByteSize/4; ++iSample)
//                    {
//                        totalSamples++;
//                        float a0 = sinf(2 * M_PI * F0 * totalSamples / 44100.f) * A0;
//                        *(pDst++) = 32768 * a0 + 32767;
//                        float a1 = sinf(2 * M_PI * F1 * totalSamples / 44100.f) * A1;
//                        *(pDst++) = 32768 * a1 + 32767;
//                    }
                }
            }
        }
        
        if (!ioData)
            return noErr;
        if (*ioActionFlags & kAudioUnitRenderAction_PreRender)
            return noErr;
        if (!(*ioActionFlags & kAudioUnitRenderAction_PostRender))
            return noErr;
        
        static NSUInteger totalDataSize = 0;
        static NSDate* beginTime;
        beginTime = [NSDate date];
        for (int i = 0; i < (int)ioData->mNumberBuffers; i++) {
            AudioBuffer *ioBuffer = &ioData->mBuffers[i];
            NSTimeInterval timeElapsed = [[NSDate date] timeIntervalSinceDate:beginTime];
            if (timeElapsed > 0)
            {
//                NSLog(@"#AUGraph# MixerRenderNotifyCallback AudioBuffer[%d] .channels=%d, .dataSize=%d; totalDataSize=%ld", i, ioBuffer->mNumberChannels, ioBuffer->mDataByteSize, totalDataSize);
            }
            else
            {
//                NSLog(@"#AUGraph# MixerRenderNotifyCallback AudioBuffer[%d] .channels=%d, .dataSize=%d; ", i, ioBuffer->mNumberChannels, ioBuffer->mDataByteSize);
            }
            
            if (ioBuffer->mData)
            {
                totalDataSize += ioBuffer->mDataByteSize;
//                NSLog(@"#AUGraph# MixerRenderNotifyCallback TimeStamp = %f", (float)totalDataSize / ioData->mBuffers[0].mNumberChannels / 2 / auController.spec.freq);
                (*auController.spec.audioMixedCallback)(auController.spec.userdata, ioBuffer->mData, ioBuffer->mDataByteSize, auController.spec.audioParams);
            }
        }
        //#AudioCallback#
        return noErr;
    }
}

static OSStatus MicInputCallback(void                        *inRefCon,
                                    AudioUnitRenderActionFlags  *ioActionFlags,
                                    const AudioTimeStamp        *inTimeStamp,
                                    UInt32                      inBusNumber,
                                    UInt32                      inNumberFrames,
                                    AudioBufferList             *ioData)
{
    @autoreleasepool {
        IJKSDLAudioUnitController* auController = (__bridge IJKSDLAudioUnitController *) inRefCon;
//        NSLog(@"#AUGraph#AudioUnitCallback# MicInputCallback : flag=0x%x, inBusNumber=%d, inNumberFrames=%d, ioData=0x%lx", *ioActionFlags, inBusNumber, inNumberFrames, (long)ioData);
        if (ioData)
        {
//            NSLog(@"#AUGraph#AudioUnitCallback# MicInputCallback : numBuffers=%d", ioData->mNumberBuffers);
            for (int i=0; i<ioData->mNumberBuffers; ++i)
            {
                AudioBuffer audioBuffer = ioData->mBuffers[i];
//                NSLog(@"#AUGraph#AudioUnitCallback# MicInputCallback : audioBuffer[%d].channels=%d, .size=%d, .data=0x%lx", i, audioBuffer.mNumberChannels, audioBuffer.mDataByteSize, (long)audioBuffer.mData);
            }
        }
        
        if (!(*ioActionFlags & kAudioUnitRenderAction_PostRender))
            return noErr;
        
        OSStatus status;
        AudioUnitRenderActionFlags actionFlag = kAudioUnitRenderAction_PostRender;
        status = AudioUnitRender(auController.mixerUnit, &actionFlag, inTimeStamp, inBusNumber, inNumberFrames, auController.audioBufferList);
//        NSLog(@"#AUGraph#AudioUnitCallback# status=%d, auController.audioBufferList=0x%lx, at %d in %s", status, (long)auController.audioBufferList, __LINE__, __PRETTY_FUNCTION__);
        return noErr;
    }
}

@end
