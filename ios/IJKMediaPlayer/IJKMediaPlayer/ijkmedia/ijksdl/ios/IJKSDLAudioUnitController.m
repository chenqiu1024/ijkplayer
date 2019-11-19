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
//#import "ijksdl/C2Buffer.h"
#import "AudioUnitManager.h"

#import <AVFoundation/AVFoundation.h>

//const int BuffersCount = 1;
//const int BufferSize = 1024 * 2 * sizeof(SInt16) * 16;

@interface IJKSDLAudioUnitController () <AudioUnitManagerDelegate>

@property (nonatomic, strong) AudioUnitManager* audioUnitManager;

@end

@implementation IJKSDLAudioUnitController {
//    BOOL _isPaused;
//    int _headPhoneOn;
}

#pragma mark    AudioUnitManagerDelegate

-(void) audioUnitManager:(AudioUnitManager *)auMgr didReceiveAudioData:(void *)data length:(int)length channel:(int)channel {
    (*_spec.audioMixedCallback)(_spec.userdata, data, length, _spec.audioParams);
}

-(void) audioUnitManager:(AudioUnitManager *)auMgr postFillPlaybackAudioData:(void *)data length:(int)length channel:(int)channel {
    _spec.callback(_spec.userdata, data, length, _spec.audioParams);
}

- (id)initWithAudioSpec:(const SDL_AudioSpec *)aSpec
{NSLog(@"#AudioDeadlock# init . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    self = [super init];
    if (self)
    {
        if (aSpec == NULL)
        {
            self = nil;
            return nil;
        }
        _spec = *aSpec;

//        _isPaused = YES;
        
        if (aSpec->format != AUDIO_S16SYS)
        {
            NSLog(@"aout_open_audio: unsupported format %d\n", (int)aSpec->format);
            return nil;
        }

        if (aSpec->channels > 6)
        {
            NSLog(@"aout_open_audio: unsupported channels %d\n", (int)aSpec->channels);
            return nil;
        }
/*
        [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionInterruptionNotification
                                                              object:self
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *note) {
                                                              BOOL ret = NO;
                                                              NSError* error = nil;
                                                              NSUInteger interruptionType = [[[note userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
                                                              if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
                                                                  ret = [[AVAudioSession sharedInstance] setActive:NO error:&error];
                                                              } else if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
                                                                  ret = [[AVAudioSession sharedInstance] setActive:YES error:&error];
                                                              }
                                                              if (!ret) {
                                                                  NSLog(@"interuptType:%d setActive failed:%@", (int)interruptionType, error);
                                                              }
                                                          }];
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:nil];
        ///!!![session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
//        [session setPreferredSampleRate:16000 error:nil];
//        NSTimeInterval bufferDuration = 0.064;
//        [session setPreferredIOBufferDuration:bufferDuration error:nil];
//        [session setMode:AVAudioSessionModeVideoChat error:nil];
//        [session setActive:YES error:nil];
        NSArray *array = session.availableInputs;
        for (int i=0; i<array.count; ++i)
        {
            AVAudioSessionPortDescription *desc = [array objectAtIndex:i];
            NSLog(@"portType: %@, portName: %@", desc.portType, desc.portName);
            if ([desc.portName containsString:@"耳机"] || [desc.portType isEqualToString:@"MicrophoneWired"] || [desc.portType containsString:@"Bluetooth"])
            {
                _headPhoneOn = 1;
                break;
            }
        }
        if (_headPhoneOn == 0)
        {
            ///!!![session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
        }
        else
        {
            [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
        }
 /*/
        self = [super init];
        if (self)
        {
            if (aSpec == NULL)
            {
                self = nil;
                return nil;
            }
            _spec = *aSpec;
            
            if (aSpec->format != AUDIO_S16SYS)
            {
                NSLog(@"aout_open_audio: unsupported format %d\n", (int)aSpec->format);
                return nil;
            }
            if (aSpec->channels > 6)
            {
                NSLog(@"aout_open_audio: unsupported channels %d\n", (int)aSpec->channels);
                return nil;
            }
            
            /* Get the current format */
            _spec.format = AUDIO_S16SYS;
            _spec.channels = 2;
            AudioStreamBasicDescription mediaASBD;
            IJKSDLGetAudioStreamBasicDescriptionFromSpec(&_spec, &mediaASBD);
            
            _audioUnitManager = [[AudioUnitManager alloc] initWithMediaSourceSpec:mediaASBD recordingOutputSpec:mediaASBD];
            [_audioUnitManager startRecording:self];
        }
        //*/
    }
    return self;
}

- (void)dealloc
{NSLog(@"#AudioDeadlock# dealloc . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    [self close];
}

//-(void) routeChangeNotification: (NSNotification *)notification {
//    int reason = [[notification.userInfo valueForKey:AVAudioSessionRouteChangeReasonKey] intValue];
//    AVAudioSessionRouteDescription *desc = (AVAudioSessionRouteDescription *)[notification.userInfo valueForKey:AVAudioSessionRouteChangePreviousRouteKey];
//    NSArray *array = desc.outputs;
//
//    if (reason == AVAudioSessionRouteChangeReasonNewDeviceAvailable)
//    {
//        for (int i=0; i<array.count; ++i)
//        {
//            AVAudioSessionPortDescription *portDesc = [array objectAtIndex:i];
//            if ([portDesc.portType isEqualToString:@"Speaker"])
//            {
//                _headPhoneOn = 1;
//                AVAudioSession *session = [AVAudioSession sharedInstance];
//                AVAudioSessionPortDescription *currentRoute = [session.currentRoute.outputs objectAtIndex:0];
//                if ([currentRoute.portType isEqualToString:@"Headphones"])
//                {
////                    if (audioDataBuffer && audioDataBuffer.count > 0) {
////                        [audioDataBuffer removeObjectAtIndex:0];
////                        playDataLength = 0;
////                    }
//                    break;
//                }
//                else
//                {
//                    for (AVAudioSessionPortDescription *desc in session.availableInputs)
//                    {
//                        if ([desc.portType isEqualToString:@"MicrophoneWired"]||[desc.portType isEqualToString:AVAudioSessionPortHeadphones] || [desc.portType isEqualToString:AVAudioSessionPortHeadsetMic])
//                        {
//                            [session setPreferredInput:desc error:nil];
//                        }
//                    }
//                    break;
//                }
//            }
//        }
//    }
//    else if(reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable)
//    {
//        for (int i=0; i<array.count; ++i)
//        {
//            AVAudioSessionPortDescription *portDesc = [array objectAtIndex:i];
//            if ([portDesc.portType isEqualToString:@"Headphones"])
//            {
//                _headPhoneOn = 0; // 没有耳机
//                AVAudioSession *session = [AVAudioSession sharedInstance];
//                ///!!![session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
//                break;
//            }
//        }
//    }
//}

- (void)play
{NSLog(@"#AudioDeadlock# play . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    /*
    if (!_auGraph)
        return;

    if (!_isPaused)
        return;
    
    _isPaused = NO;
    NSError *error = nil;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(routeChangeNotification:)name:AVAudioSessionRouteChangeNotification object:[AVAudioSession sharedInstance]];
    
    if (NO == [[AVAudioSession sharedInstance] setActive:YES error:&error]) {
        NSLog(@"AudioUnit: AVAudioSession.setActive(YES) failed: %@\n", error ? [error localizedDescription] : @"nil");
    }

    OSStatus status = AUGraphStart(_auGraph);
    NSLog(@"#AudioUnitCallback# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
    status = AUGraphStart(_auGraph1);
    NSLog(@"#AudioUnitCallback# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
    /*/
    [_audioUnitManager startPlaying];
    //*/
}

- (void)pause
{NSLog(@"#AudioDeadlock# pause . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    /*
    if (!_auGraph)
        return;

    _isPaused = YES;
    OSStatus status = AUGraphStop(_auGraph);
    if (status != noErr)
        ALOGE("AudioUnit: failed to stop AudioUnit (%d)\n", (int)status);
    status = AUGraphStop(_auGraph1);
    NSLog(@"#AudioUnitCallback# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
    /*/
    [_audioUnitManager stopPlaying];
    //*/
}

- (void)stop
{NSLog(@"#AudioDeadlock# stop . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    /*
    if (!_auGraph)
        return;

//    for (C2Buffer* c2buffer in _c2Buffers)
//    {
//        [c2buffer finish];
//    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    OSStatus status = AUGraphStop(_auGraph);
    if (status != noErr)
        ALOGE("AudioUnit: failed to stop AudioUnit (%d)", (int)status);
    status = AUGraphStop(_auGraph1);
    NSLog(@"#AudioUnitCallback# status=%d, at %d in %s", status, __LINE__, __PRETTY_FUNCTION__);
    /*/
    [_audioUnitManager stopPlaying];
    //*/;
}

- (void)close
{NSLog(@"#AudioDeadlock# close . at %d in %s", __LINE__, __PRETTY_FUNCTION__);
    /*
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
    AUGraphClose(_auGraph1);
    _auGraph1 = NULL;
    
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
    /*/
    [_audioUnitManager finish];
    //*/
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

@end
