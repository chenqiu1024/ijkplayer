//
//  C2Buffer.m
//  LeetCodePlayground
//
//  Created by DOM QIU on 2019/5/11.
//  Copyright © 2019 Cyllenge. All rights reserved.
//

#import "C2Buffer.h"
#import <stdlib.h>
#import <string.h>

//#define ENABLE_C2BUFFER_LOG

@interface C2Buffer ()
{
    uint8_t* _buffer;
//    uint32_t _bytesFilledSubtrahends[2];
    bool _isConsumerLive[2];
    size_t _bytesRead[2];
    size_t _readLocations[2];
    
    NSCondition* _cond;
}

@property (nonatomic, assign) size_t bytesWritten;

@property (nonatomic, assign) size_t writeLocation;
@property (nonatomic, assign) size_t fetchingSize;

@property (nonatomic, assign) size_t size;

@end

@implementation C2Buffer

-(void) dealloc {
    free(_buffer);
}

-(instancetype) initWithSize:(size_t)size delegate:(_Nonnull id<C2BufferDelegate>)delegate {
    if (self = [super init])
    {
        _delegate = delegate;
        
        _buffer = (uint8_t*) malloc(size);
        
        _size = size;
        
        _writeLocation  = 0;
        _readLocations[0] = 0;
        _readLocations[1] = 0;
        _fetchingSize = 0;
        
        _bytesWritten = 0;
        _bytesRead[0] = 0;
        _bytesRead[1] = 0;
        
        _isConsumerLive[0] = NO;
        _isConsumerLive[1] = NO;
        
        _cond = [[NSCondition alloc] init];
    }
    return self;
}

-(void) notifyConsumerWillDeactive:(int)consumerIndex {
    [_cond lock];
    {
        _isConsumerLive[consumerIndex] = NO;
        [_cond broadcast];
    }
    [_cond unlock];
}

-(void) finish {
    [self notifyConsumerWillDeactive:0];
    [self notifyConsumerWillDeactive:1];
}

-(size_t) readBytesForConsumer:(int)consumerIndex into:(void*)destBuffer length:(size_t)length isFinal:(BOOL)isFinal {
    _isConsumerLive[consumerIndex] = YES;
    size_t lengthLeft = length;
    uint8_t* pDst = (uint8_t*)destBuffer;
    while (lengthLeft > 0)
    {
        size_t readyBytesLeft = 0;
        [_cond lock];
        {
            if (_bytesWritten <= _bytesRead[consumerIndex])
            {
#ifdef ENABLE_C2BUFFER_LOG
                NSLog(@"#C2Buffer#Deadlock# _bytesWritten=%ld <= _bytesRead[%d]=%ld, at %d in %s", _bytesWritten, consumerIndex, _bytesRead[consumerIndex], __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
                if (_fetchingSize > 0)
                {
#ifdef ENABLE_C2BUFFER_LOG
                    NSLog(@"#C2Buffer#Deadlock# _fetchingSize=%ld so wait, at %d in %s", _fetchingSize, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
                    while (_bytesWritten <= _bytesRead[consumerIndex])
                    {
                        [_cond wait];
                    }
                    [_cond unlock];
#ifdef ENABLE_C2BUFFER_LOG
                    NSLog(@"#C2Buffer#Deadlock# _bytesWritten=%ld > _bytesRead[%d]=%ld then continue, at %d in %s", _bytesWritten, consumerIndex, _bytesRead[consumerIndex], __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
                    continue;
                }
                else
                {
                    size_t minBytesRead = _bytesRead[consumerIndex];
                    if (_isConsumerLive[1-consumerIndex])
                    {
                        minBytesRead = minBytesRead < _bytesRead[1-consumerIndex] ? minBytesRead : _bytesRead[1-consumerIndex];
                    }
                    size_t emptyBytesCount = _size - _bytesWritten + minBytesRead;
                    while (emptyBytesCount <= 0 && _bytesWritten <= _bytesRead[consumerIndex] && _fetchingSize <= 0 && _isConsumerLive[1-consumerIndex])
                    {
#ifdef ENABLE_C2BUFFER_LOG
                        NSLog(@"#C2Buffer#Deadlock# emptyBytesCount = _size(=%ld) - _bytesWritten(=%ld) + min(_bytesRead[0]=%ld, _bytesRead[1]=%ld) = %ld <=0 so wait, at %d in %s", _size, _bytesWritten, _bytesRead[0], _bytesRead[1], emptyBytesCount, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
                        [_cond wait];
                        
                        minBytesRead = _bytesRead[consumerIndex];
                        if (_isConsumerLive[1-consumerIndex])
                        {
                            minBytesRead = minBytesRead < _bytesRead[1-consumerIndex] ? minBytesRead : _bytesRead[1-consumerIndex];
                        }
                        emptyBytesCount = _size - _bytesWritten + minBytesRead;
                    }
                    if (_bytesWritten > _bytesRead[consumerIndex])
                    {
                        [_cond unlock];
                        continue;
                    }
                    if (_fetchingSize > 0)
                    {
                        [_cond unlock];
                        continue;
                    }
#ifdef ENABLE_C2BUFFER_LOG
                    NSLog(@"#C2Buffer#Deadlock# emptyBytesCount = _size(=%ld) - _bytesWritten(=%ld) + min(_bytesRead[0]=%ld, _bytesRead[1]=%ld) = %ld > 0, at %d in %s", _size, _bytesWritten, _bytesRead[0], _bytesRead[0], emptyBytesCount, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
                    _fetchingSize = emptyBytesCount < lengthLeft ? emptyBytesCount : lengthLeft;
#ifdef ENABLE_C2BUFFER_LOG
                    NSLog(@"#C2Buffer#Deadlock# _fetchingSize = min(lengthLeft=%ld, emptyBytesCount=%ld) = %ld, at %d in %s", lengthLeft, emptyBytesCount, _fetchingSize, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
                    size_t distanceToEnd = _size - _writeLocation;
                    _fetchingSize = distanceToEnd < _fetchingSize ? distanceToEnd : _fetchingSize;
#ifdef ENABLE_C2BUFFER_LOG
                    NSLog(@"#C2Buffer#Deadlock# _fetchingSize = min(_fetchingSize, distanceToEnd=(_size - _writeLocation)=(%ld-%ld)=%ld) = %ld, at %d in %s", _size, _writeLocation, distanceToEnd, _fetchingSize, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
                }
            }
            else
            {
                size_t readyBytesCount = _bytesWritten - _bytesRead[consumerIndex];
                readyBytesLeft = readyBytesCount < lengthLeft ? readyBytesCount : lengthLeft;
#ifdef ENABLE_C2BUFFER_LOG
                NSLog(@"#C2Buffer#Deadlock# readyBytesCount=_bytesWritten - _bytesRead[%d]=%ld-%ld=%ld, readyBytesLeft=min(readyBytesCount, lengthLeft=%ld)=%ld, at %d in %s", consumerIndex, _bytesWritten, _bytesRead[consumerIndex], readyBytesCount, lengthLeft, readyBytesLeft, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
            }
        }
        [_cond unlock];
        
        if (readyBytesLeft > 0)
        {
            size_t tmp = readyBytesLeft;///???
            while (readyBytesLeft > 0)
            {
                size_t distanceToEnd = _size - _readLocations[consumerIndex];
                size_t segmentLength = distanceToEnd > readyBytesLeft ? readyBytesLeft : distanceToEnd;
                memcpy(pDst, _buffer + _readLocations[consumerIndex], segmentLength);
                _readLocations[consumerIndex] += segmentLength;
                if (_size == _readLocations[consumerIndex])
                {
                    _readLocations[consumerIndex] = 0;
                }
                
                pDst += segmentLength;
                readyBytesLeft -= segmentLength;
                lengthLeft -= segmentLength;
            }
            
            [_cond lock];
            {
                _bytesRead[consumerIndex] += tmp;///???
#ifdef ENABLE_C2BUFFER_LOG
                NSLog(@"#C2Buffer#Deadlock# _bytesRead[%d]+=%ld=%ld, at %d in %s", consumerIndex, tmp, _bytesRead[consumerIndex], __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
                size_t subtrahend = _bytesRead[0] < _bytesRead[1] ? _bytesRead[0] : _bytesRead[1];
                if (subtrahend > 0)
                {
                    _bytesRead[0] -= subtrahend;
                    _bytesRead[1] -= subtrahend;
                    _bytesWritten -= subtrahend;
#ifdef ENABLE_C2BUFFER_LOG
                    NSLog(@"#C2Buffer#Deadlock# After subtraction : _bytesRead[0]=%ld, _bytesRead[1]=%ld, _bytesWritten=%ld, at %d in %s", _bytesRead[0], _bytesRead[1], _bytesWritten, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
                    [_cond broadcast];
                }
            }
            [_cond unlock];
        }
        else if (_fetchingSize > 0)
        {
            while (_fetchingSize > 0)
            {
                size_t actualFetchedCount = [_delegate c2BufferFillDataTo:(_buffer + _writeLocation) length:_fetchingSize];
                [_cond lock];
                {
                    _writeLocation += actualFetchedCount;
                    if (_size == _writeLocation)
                    {
                        _writeLocation = 0;
                    }
                    _fetchingSize -= actualFetchedCount;
                    _bytesWritten += actualFetchedCount;
#ifdef ENABLE_C2BUFFER_LOG
                    NSLog(@"#C2Buffer#Deadlock# After fetching %ld bytes : _fetchingSize=%ld, _bytesWritten=%ld, at %d in %s", actualFetchedCount, _fetchingSize, _bytesWritten, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG
                    [_cond broadcast];
                }
                [_cond unlock];
            }
        }
    }
    if (isFinal)
    {
        [self notifyConsumerWillDeactive:consumerIndex];
    }
    return length - lengthLeft;
}

@end


@interface C2BufferTest () <C2BufferDelegate>

@property (nonatomic, assign) uint8_t number;

@end

@implementation C2BufferTest

-(size_t) c2BufferFillDataTo:(void *)buffer length:(size_t)length {
    uint8_t* pDst = (uint8_t*)buffer;
    for (int i=0; i<length; ++i)
    {
        *pDst++ = (++_number);
    }
    return length;
}

+(void) test {
    const size_t MinBufferSize = 2;
    const size_t MaxBufferSize = 16;
    const size_t MinFrameSize = 1;
    const size_t MaxFrameSize = 32;
    
    const size_t TestCount = 1024;
    const size_t InvokeCount = 256;
    
    long seed = [NSDate date].timeIntervalSince1970;
    srand48(seed);
    
    C2BufferTest* tester = [[C2BufferTest alloc] init];
    tester.number = 0;
    dispatch_group_t dispatchGroup = dispatch_group_create();
    for (int iTest=0; iTest<TestCount; ++iTest)
    {
        size_t bufferSize = lrand48() % (MaxBufferSize - MinBufferSize + 1) + MinBufferSize;
        C2Buffer* c2buffer = [[C2Buffer alloc] initWithSize:bufferSize delegate:tester];
        for (int c=0; c<2; ++c)
        {
            dispatch_group_async(dispatchGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                uint8_t* destBuffer = malloc(MaxFrameSize + 1);
                destBuffer[0] = 0;
                for (int j=0; j<InvokeCount; ++j)
                {
                    BOOL passed = YES;
                    size_t frameSize = lrand48() % (MaxFrameSize - MinFrameSize + 1) + MinFrameSize;
                    [c2buffer readBytesForConsumer:c into:&destBuffer[1] length:frameSize isFinal:(j == InvokeCount - 1)];
                    
                    for (int i=0; i<frameSize; ++i)
                    {
                        if (destBuffer[i] + 1 != destBuffer[i+1] && (destBuffer[i] != 255 || destBuffer[i+1] != 0))
                        {
                            passed = NO;
                            NSLog(@"#C2Buffer# Error");
                        }
                    }
                    
                    destBuffer[0] = destBuffer[frameSize];
                    
                    if (passed)
                        NSLog(@"#C2Buffer# Passed : Test#%d Consumer#%d Block#%d", iTest, c, j);
                }
                free(destBuffer);
            });
        }
        dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
    }
    
}

@end
