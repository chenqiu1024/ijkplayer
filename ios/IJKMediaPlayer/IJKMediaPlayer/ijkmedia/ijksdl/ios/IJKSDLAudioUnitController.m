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

#import <AVFoundation/AVFoundation.h>

const int BuffersCount = 1;
const int BufferSize = 1024 * 2 * sizeof(SInt16) * 16;

@interface IJKSDLAudioUnitController ()

@property (nonatomic, assign) AudioUnit ioUnit;
@property (nonatomic, assign) AudioUnit resampleUnit;
@property (nonatomic, assign) AudioUnit mixerUnit;
//@property (nonatomic, assign) AudioUnit inputUnit;

@property (nonatomic, assign) AudioBufferList* audioBufferList;

@end

@implementation IJKSDLAudioUnitController {
//    AudioUnit _auUnit;
    AUGraph _auGraph;
    BOOL _isPaused;
}

- (id)initWithAudioSpec:(const SDL_AudioSpec *)aSpec
{
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

        NewAUGraph(&_auGraph);
        
        AUNode outputNode, mixerNode, resampleNode;
//        AUNode inputNode;
        AudioComponentDescription outputACDesc, mixerACDesc, resampleACDesc;
//        AUNode inputACDesc;
        
//        IJKSDLGetAudioComponentDescriptionFromSpec(&_spec, &mixerACDesc);
        mixerACDesc.componentType = kAudioUnitType_Mixer;
        mixerACDesc.componentSubType = kAudioUnitSubType_MultiChannelMixer;
        mixerACDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
        mixerACDesc.componentFlags = 0;
        mixerACDesc.componentFlagsMask = 0;
        
        IJKSDLGetAudioComponentDescriptionFromSpec(&_spec, &outputACDesc);
        
//        IJKSDLGetAudioComponentDescriptionFromSpec(&_spec, &inputACDesc);

        resampleACDesc.componentType = kAudioUnitType_FormatConverter;
        resampleACDesc.componentSubType = kAudioUnitSubType_AUConverter;
        resampleACDesc.componentFlags = 0;
        resampleACDesc.componentFlagsMask = 0;
        resampleACDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
        
//        AUGraphAddNode(_auGraph, &inputACDesc, &inputNode);
        AUGraphAddNode(_auGraph, &outputACDesc, &outputNode);
        AUGraphAddNode(_auGraph, &resampleACDesc, &resampleNode);
        AUGraphAddNode(_auGraph, &mixerACDesc, &mixerNode);
        AUGraphConnectNodeInput(_auGraph, mixerNode, 0, outputNode, 0);
        AUGraphConnectNodeInput(_auGraph, outputNode, 1, resampleNode, 0);
        AUGraphConnectNodeInput(_auGraph, resampleNode, 0, mixerNode, 1);
        
        AUGraphOpen(_auGraph);
        
//        AUGraphNodeInfo(_auGraph, inputNode, NULL, &_inputUnit);
        AUGraphNodeInfo(_auGraph, outputNode, NULL, &_ioUnit);
        AUGraphNodeInfo(_auGraph, mixerNode, NULL, &_mixerUnit);
        AUGraphNodeInfo(_auGraph, resampleNode, NULL, &_resampleUnit);
        
        OSStatus status;
        
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
        
        UInt32 busCount = 2;
        status = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &busCount, sizeof(busCount));
        
        UInt32 maximumFramesPerSlice = 4096;
        status = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFramesPerSlice, sizeof(maximumFramesPerSlice));

        /* Get the current format */
        _spec.format = AUDIO_S16SYS;
        _spec.channels = 2;
        AudioStreamBasicDescription streamDescription;
        IJKSDLGetAudioStreamBasicDescriptionFromSpec(&_spec, &streamDescription);

        _audioBufferList = (AudioBufferList*)malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer) * (BuffersCount - 1));
        _audioBufferList->mNumberBuffers = BuffersCount;
        for (int i=0; i<BuffersCount; ++i)
        {
            _audioBufferList->mBuffers[i].mNumberChannels = 1;
            _audioBufferList->mBuffers[i].mDataByteSize = BufferSize;
            _audioBufferList->mBuffers[i].mData = malloc(BufferSize);
        }
        
        /* Set the desired format */
        UInt32 sizeOfASBD = sizeof(AudioStreamBasicDescription);
        status = AudioUnitSetProperty(_mixerUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      0,
                                      &streamDescription,
                                      sizeOfASBD);
        double sampleRate = _spec.freq;
        status = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, 0, &sampleRate, sizeof(sampleRate));;
        
        status = AudioUnitSetProperty(_ioUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      0,
                                      &streamDescription,
                                      sizeOfASBD);
        AudioStreamBasicDescription micInASBD = streamDescription;
        micInASBD.mSampleRate = _spec.freq;///44100;///
//        micInASBD.mFormatID = kAudioFormatLinearPCM;
//        micInASBD.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsNonInterleaved;
//        micInASBD.mFramesPerPacket = 1;
        micInASBD.mChannelsPerFrame = 1;
        micInASBD.mBytesPerPacket = 2;
        micInASBD.mBytesPerFrame = 2;
//        micInASBD.mBitsPerChannel = 16;
        status = AudioUnitSetProperty(_ioUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output,
                                      1,
                                      &micInASBD,
                                      sizeOfASBD);
        
        AURenderCallbackStruct callback;
        callback.inputProc = (AURenderCallback) RenderCallback;
        callback.inputProcRefCon = (__bridge void*) self;
        AUGraphSetNodeInputCallback(_auGraph, mixerNode, 0, &callback);
        
        AudioStreamBasicDescription ioASBDIn;
        AudioStreamBasicDescription ioASBDOut;
        AudioUnitGetProperty(_ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &ioASBDIn, &sizeOfASBD);
        AudioUnitGetProperty(_ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &ioASBDOut, &sizeOfASBD);
        
        status = AudioUnitSetProperty(_resampleUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &ioASBDIn, sizeOfASBD);
        status = AudioUnitSetProperty(_resampleUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &ioASBDOut, sizeOfASBD);
        
        AURenderCallbackStruct inputCallback;
        inputCallback.inputProc = (AURenderCallback) InputCallback;
        inputCallback.inputProcRefCon = (__bridge void*) self;
        status = AudioUnitAddRenderNotify(_mixerUnit, (AURenderCallback)InputCallback, (__bridge void*)self);
//        status = AudioUnitSetProperty(_ioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &inputCallback, sizeof(inputCallback));
        NSLog(@"#RecordCallback# Set render notify = %d", status);
        
        SDL_CalculateAudioSpec(&_spec);
        
        AUGraphInitialize(_auGraph);
        
        CAShow(_auGraph);
        
        ////////////////////
//        AudioComponentDescription desc;
//        IJKSDLGetAudioComponentDescriptionFromSpec(&_spec, &desc);
//
//        AudioComponent auComponent = AudioComponentFindNext(NULL, &desc);
//        if (auComponent == NULL) {
//            ALOGE("AudioUnit: AudioComponentFindNext failed");
//            self = nil;
//            return nil;
//        }
//
//        AudioUnit auUnit;
//        OSStatus status = AudioComponentInstanceNew(auComponent, &auUnit);
//        if (status != noErr) {
//            ALOGE("AudioUnit: AudioComponentInstanceNew failed");
//            self = nil;
//            return nil;
//        }
//
//        UInt32 flag = 1;
//        status = AudioUnitSetProperty(auUnit,
//                                      kAudioOutputUnitProperty_EnableIO,
//                                      kAudioUnitScope_Output,
//                                      0,
//                                      &flag,
//                                      sizeof(flag));
//        if (status != noErr) {
//            ALOGE("AudioUnit: failed to set IO mode (%d)", (int)status);
//        }
//
//        /* Get the current format */
//        _spec.format = AUDIO_S16SYS;
//        _spec.channels = 2;
//        AudioStreamBasicDescription streamDescription;
//        IJKSDLGetAudioStreamBasicDescriptionFromSpec(&_spec, &streamDescription);
//
//        /* Set the desired format */
//        UInt32 i_param_size = sizeof(streamDescription);
//        status = AudioUnitSetProperty(auUnit,
//                                      kAudioUnitProperty_StreamFormat,
//                                      kAudioUnitScope_Input,
//                                      0,
//                                      &streamDescription,
//                                      i_param_size);
//        if (status != noErr) {
//            ALOGE("AudioUnit: failed to set stream format (%d)", (int)status);
//            self = nil;
//            return nil;
//        }
//
//        /* Retrieve actual format */
//        status = AudioUnitGetProperty(auUnit,
//                                      kAudioUnitProperty_StreamFormat,
//                                      kAudioUnitScope_Input,
//                                      0,
//                                      &streamDescription,
//                                      &i_param_size);
//        if (status != noErr) {
//            ALOGE("AudioUnit: failed to verify stream format (%d)\n", (int)status);
//        }
//
//        AURenderCallbackStruct callback;
//        callback.inputProc = (AURenderCallback) RenderCallback;
//        callback.inputProcRefCon = (__bridge void*) self;
//        status = AudioUnitSetProperty(auUnit,
//                                      kAudioUnitProperty_SetRenderCallback,
//                                      kAudioUnitScope_Input,
//                                      0, &callback, sizeof(callback));
//        if (status != noErr) {
//            ALOGE("AudioUnit: render callback setup failed (%d)\n", (int)status);
//            self = nil;
//            return nil;
//        }
//
//        SDL_CalculateAudioSpec(&_spec);
//
////        AudioUnitSetParameter(auUnit, kAudioUnitParameterUnit_Rate, kAudioUnitScope_Input, 1, 2.0f, 0);
//
//        /* AU initiliaze */
//        status = AudioUnitInitialize(auUnit);
//        if (status != noErr) {
//            ALOGE("AudioUnit: AudioUnitInitialize failed (%d)\n", (int)status);
//            self = nil;
//            return nil;
//        }
//
//        _auUnit = auUnit;
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

- (void)play
{
    if (!_auGraph)
        return;

    _isPaused = NO;
    NSError *error = nil;
    if (NO == [[AVAudioSession sharedInstance] setActive:YES error:&error]) {
        NSLog(@"AudioUnit: AVAudioSession.setActive(YES) failed: %@\n", error ? [error localizedDescription] : @"nil");
    }

    OSStatus status = AUGraphStart(_auGraph);
    if (status != noErr)
        NSLog(@"AudioUnit: AudioOutputUnitStart failed (%d)\n", (int)status);
}

- (void)pause
{
    if (!_auGraph)
        return;

    _isPaused = YES;
    OSStatus status = AUGraphStop(_auGraph);
    if (status != noErr)
        ALOGE("AudioUnit: failed to stop AudioUnit (%d)\n", (int)status);
}

- (void)flush
{
    if (!_auGraph)
        return;

///!!!    AudioUnitReset(_auUnit, kAudioUnitScope_Global, 0);
}

- (void)stop
{
    if (!_auGraph)
        return;

    OSStatus status = AUGraphStop(_auGraph);
    if (status != noErr)
        ALOGE("AudioUnit: failed to stop AudioUnit (%d)", (int)status);
}

- (void)close
{
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
    
    if (self.audioBufferList)
    {
        for (int i=0; i<_audioBufferList->mNumberBuffers; ++i)
        {
            if (_audioBufferList->mBuffers[i].mData)
                free(_audioBufferList->mBuffers[i].mData);
        }
        free(_audioBufferList);
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

static OSStatus RenderCallback(void                        *inRefCon,
                               AudioUnitRenderActionFlags  *ioActionFlags,
                               const AudioTimeStamp        *inTimeStamp,
                               UInt32                      inBusNumber,
                               UInt32                      inNumberFrames,
                               AudioBufferList             *ioData)
{
    @autoreleasepool {
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
            (*auController.spec.callback)(auController.spec.userdata, ioBuffer->mData, ioBuffer->mDataByteSize, auController.spec.audioParams);
        }
        //#AudioCallback#
        return noErr;
    }
}

static OSStatus InputCallback(void                        *inRefCon,
                               AudioUnitRenderActionFlags  *ioActionFlags,
                               const AudioTimeStamp        *inTimeStamp,
                               UInt32                      inBusNumber,
                               UInt32                      inNumberFrames,
                               AudioBufferList             *ioData)
{
    @autoreleasepool {
        IJKSDLAudioUnitController* auController = (__bridge IJKSDLAudioUnitController *) inRefCon;
        NSLog(@"#RecordCallback# AudioUnitRender: inBusNumber=%d, inNumberFrames=%d, ioData=0x%lx", inBusNumber, inNumberFrames, (long)ioData);
//        inBusNumber = 0;///!!!
//        OSStatus status = AudioUnitRender(auController.resampleUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, auController.audioBufferList);
//        if (status != noErr)
//        {
//            NSLog(@"#RecordCallback# AudioUnitRender error:%d, inBusNumber=%d, inNumberFrames=%d, ioData=0x%lx", status, inBusNumber, inNumberFrames, (long)ioData);
//        }
//        else
//        {
//            NSLog(@"#RecordCallback# AudioUnitRender success. inBusNumber=%d, inNumberFrames=%d, ioData=0x%lx", inBusNumber, inNumberFrames, (long)ioData);
//        }

//        if (!auController || auController->_isPaused) {
//            for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
//                AudioBuffer *ioBuffer = &ioData->mBuffers[i];
//                memset(ioBuffer->mData, auController.spec.silence, ioBuffer->mDataByteSize);
//            }
//            return noErr;
//        }
//
        if (!ioData)
            return noErr;
        
        for (int i = 0; i < (int)ioData->mNumberBuffers; i++) {
            AudioBuffer *ioBuffer = &ioData->mBuffers[i];
            (*auController.spec.audioMixedCallback)(auController.spec.userdata, ioBuffer->mData, ioBuffer->mDataByteSize, auController.spec.audioParams);
        }
        
        //#AudioCallback#
        return noErr;
    }
}

@end
