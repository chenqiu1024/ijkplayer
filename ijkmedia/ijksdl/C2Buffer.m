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

//#define ENABLE_C2BUFFER_LOG_VERBOSE
//#define ENABLE_C2BUFFER_LOG_DEBUG

@interface C2Buffer ()
{
    uint8_t* _buffer;
//    uint32_t _bytesFilledSubtrahends[2];
    bool _isConsumerLive[2];
    int32_t _bytesRead[2];
    int32_t _readLocations[2];
    int _finishedThreads;
    
    NSCondition* _cond;
}

@property (nonatomic, assign) int32_t bytesWritten;

@property (nonatomic, assign) int32_t writeLocation;
@property (nonatomic, assign) int32_t fetchingSize;

@property (nonatomic, assign) int32_t size;

@end

@implementation C2Buffer

-(void) dealloc {
    if (_buffer)
        free(_buffer);
}

-(instancetype) initWithSize:(int32_t)size delegate:(_Nonnull id<C2BufferDelegate>)delegate {
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
        
        _isConsumerLive[0] = YES;
        _isConsumerLive[1] = YES;
        _finishedThreads = 0;
        
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

-(int32_t) readBytesForConsumer:(int)consumerIndex into:(void*)destBuffer length:(int32_t)length isFinal:(BOOL)isFinal completion:(void(^)(int32_t))completion {
#ifdef ENABLE_C2BUFFER_LOG_DEBUG
    NSLog(@"#C2Buffer#Deadlock# readBytesForConsumer:%d length:%d isFinal:%d", consumerIndex, length, isFinal);
#endif //#ifdef ENABLE_C2BUFFER_LOG_DEBUG
    _isConsumerLive[consumerIndex] = YES;
    int32_t lengthLeft = length;
    uint8_t* pDst = (uint8_t*)destBuffer;
    while (lengthLeft > 0)
    {
        int32_t readyBytesLeft = 0;
        [_cond lock];
        {
            if (_bytesWritten <= _bytesRead[consumerIndex])
            {
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                NSLog(@"#C2Buffer#Deadlock# _bytesWritten=%d <= _bytesRead[%d]=%d, at %d in %s", _bytesWritten, consumerIndex, _bytesRead[consumerIndex], __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                if (_fetchingSize > 0)
                {
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    NSLog(@"#C2Buffer#Deadlock# _fetchingSize=%d so wait, at %d in %s", _fetchingSize, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    while (_bytesWritten <= _bytesRead[consumerIndex])
                    {
                        [_cond wait];
                    }
                    [_cond unlock];
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    NSLog(@"#C2Buffer#Deadlock# _bytesWritten=%d > _bytesRead[%d]=%d then continue, at %d in %s", _bytesWritten, consumerIndex, _bytesRead[consumerIndex], __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    continue;
                }
                else
                {
                    int32_t minBytesRead = _bytesRead[consumerIndex];
                    if (_isConsumerLive[1-consumerIndex])
                    {
                        minBytesRead = minBytesRead < _bytesRead[1-consumerIndex] ? minBytesRead : _bytesRead[1-consumerIndex];
                    }
                    int32_t emptyBytesCount = _size - _bytesWritten + minBytesRead;
                    while (emptyBytesCount <= 0 && _bytesWritten <= _bytesRead[consumerIndex] && _fetchingSize <= 0 && _isConsumerLive[1-consumerIndex])
                    {
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                        NSLog(@"#C2Buffer#Deadlock# emptyBytesCount = _size(=%d) - _bytesWritten(=%d) + min(_bytesRead[0]=%d, _bytesRead[1]=%d) = %d <=0 so wait, at %d in %s", _size, _bytesWritten, _bytesRead[0], _bytesRead[1], emptyBytesCount, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
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
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    NSLog(@"#C2Buffer#Deadlock# emptyBytesCount = _size(=%d) - _bytesWritten(=%d) + min(_bytesRead[0]=%d, _bytesRead[1]=%d) = %d > 0, at %d in %s", _size, _bytesWritten, _bytesRead[0], _bytesRead[1], emptyBytesCount, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    _fetchingSize = emptyBytesCount < lengthLeft ? emptyBytesCount : lengthLeft;
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    NSLog(@"#C2Buffer#Deadlock# _fetchingSize = min(lengthLeft=%d, emptyBytesCount=%d) = %d, at %d in %s", lengthLeft, emptyBytesCount, _fetchingSize, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    int32_t distanceToEnd = _size - _writeLocation;
                    _fetchingSize = distanceToEnd < _fetchingSize ? distanceToEnd : _fetchingSize;
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    NSLog(@"#C2Buffer#Deadlock# _fetchingSize = min(_fetchingSize, distanceToEnd=(_size - _writeLocation)=(%d-%d)=%d) = %d, at %d in %s", _size, _writeLocation, distanceToEnd, _fetchingSize, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                }
            }
            else
            {
                int32_t readyBytesCount = _bytesWritten - _bytesRead[consumerIndex];
                readyBytesLeft = readyBytesCount < lengthLeft ? readyBytesCount : lengthLeft;
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                NSLog(@"#C2Buffer#Deadlock# readyBytesCount=_bytesWritten - _bytesRead[%d]=%d-%d=%d, readyBytesLeft=min(readyBytesCount, lengthLeft=%d)=%d, at %d in %s", consumerIndex, _bytesWritten, _bytesRead[consumerIndex], readyBytesCount, lengthLeft, readyBytesLeft, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
            }
        }
        [_cond unlock];
        
        if (readyBytesLeft > 0)
        {
            int32_t tmp = readyBytesLeft;///???
            while (readyBytesLeft > 0)
            {
                int32_t distanceToEnd = _size - _readLocations[consumerIndex];
                int32_t segmentLength = distanceToEnd > readyBytesLeft ? readyBytesLeft : distanceToEnd;
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
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                NSLog(@"#C2Buffer#Deadlock# _bytesRead[%d]+=%d=%d, at %d in %s", consumerIndex, tmp, _bytesRead[consumerIndex], __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                int32_t subtrahend = _bytesRead[0] < _bytesRead[1] ? _bytesRead[0] : _bytesRead[1];
                if (subtrahend > 0)
                {
                    _bytesRead[0] -= subtrahend;
                    _bytesRead[1] -= subtrahend;
                    _bytesWritten -= subtrahend;
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    NSLog(@"#C2Buffer#Deadlock# After subtraction : _bytesRead[0]=%d, _bytesRead[1]=%d, _bytesWritten=%d, at %d in %s", _bytesRead[0], _bytesRead[1], _bytesWritten, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    [_cond broadcast];
                }
            }
            [_cond unlock];
        }
        else if (_fetchingSize > 0)
        {
            while (_fetchingSize > 0)
            {
                int32_t actualFetchedCount = [_delegate c2BufferFillDataTo:(_buffer + _writeLocation) length:_fetchingSize];
                [_cond lock];
                {
                    _writeLocation += actualFetchedCount;
                    if (_size == _writeLocation)
                    {
                        _writeLocation = 0;
                    }
                    _fetchingSize -= actualFetchedCount;
                    _bytesWritten += actualFetchedCount;
#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    NSLog(@"#C2Buffer#Deadlock# After fetching %d bytes : _fetchingSize=%d, _bytesWritten=%d, at %d in %s", actualFetchedCount, _fetchingSize, _bytesWritten, __LINE__, __PRETTY_FUNCTION__);
#endif //#ifdef ENABLE_C2BUFFER_LOG_VERBOSE
                    [_cond broadcast];
                }
                [_cond unlock];
            }
        }
    }
    if (isFinal)
    {
        [self notifyConsumerWillDeactive:consumerIndex];
        [_cond lock];
        {
            if (_finishedThreads < 2)
            {
                if (++_finishedThreads == 2)
                {
                    free(_buffer);
                    _buffer = NULL;
                }
            }
        }
        [_cond unlock];
    }
    
    if (completion)
    {
        completion(length - lengthLeft);
    }
    return length - lengthLeft;
}

@end


@interface C2BufferTest () <C2BufferDelegate>

@property (nonatomic, assign) uint8_t number;

@end

@implementation C2BufferTest

-(int32_t) c2BufferFillDataTo:(void *)buffer length:(int32_t)length {
    uint8_t* pDst = (uint8_t*)buffer;
    for (int i=0; i<length; ++i)
    {
        *pDst++ = (++_number);
    }
    return length;
}

#define GIVEN_TESTCASE
const int32_t TestCaseBufferSize = 8;
const int32_t TestCaseInvokeCount = 16;
const int32_t TestCaseMaxFrameSize = 8;
//int32_t TestCaseFrameSizes[2][32] = {{14, 14, 8, 8, 11, 3, 5, 13, 10, 3, 12, 10, 8, 3, 6, 15, 12, 6, 13, 2, 9, 6, 13, 14, 14, 5, 7, 4, 3, 6, 14, 3}, {6, 0, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 30, 42, 0, 29, 2, 43, 0, 0, 0, 0, 0, 22, 50, 64, 52, 1, 47}};
//int32_t TestCaseFrameSizes[2][32] = {{8, 9, 3, 11, 13, 2, 12, 7, 16, 8, 5, 13, 6, 4, 5, 13, 12, 9, 14, 2, 2, 15, 10, 8, 11, 7, 12, 8, 10, 9, 2, 3}, {3, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10}};
const int32_t TestCaseFrameSizes[2][TestCaseInvokeCount] = {{6, 8, 7, 0, 19, 7, 3, 3, 6, 5, 7, 8, 5, 5, 7, 2}, {4, 6, 2, 3, 5, 2, 8, 6, 4, 5, 3, 8, 7, 8, 7, 2}};

+(void) test {
    const int32_t MinBufferSize = 6;
    const int32_t MaxBufferSize = 8;
    const NSArray<NSNumber* >* MinFrameSizes = @[@(2), @(2)];
#ifdef GIVEN_TESTCASE
    const NSArray<NSNumber* >* MaxFrameSizes = @[@(TestCaseMaxFrameSize), @(TestCaseMaxFrameSize)];
#else
    const NSArray<NSNumber* >* MaxFrameSizes = @[@(8), @(8)];
#endif
    
    const int32_t TestCount = 65536;
#ifdef GIVEN_TESTCASE
    const int32_t InvokeCount = TestCaseInvokeCount;
#else
    const int32_t InvokeCount = 16;
#endif
    
    long seed = [NSDate date].timeIntervalSince1970;
    srand48(seed);
    
    C2BufferTest* tester = [[C2BufferTest alloc] init];
    dispatch_group_t dispatchGroup = dispatch_group_create();
    for (int iTest=0; iTest<TestCount; ++iTest)
    {
#ifdef GIVEN_TESTCASE
        int32_t bufferSize = TestCaseBufferSize;
#else
        int32_t bufferSize = lrand48() % (MaxBufferSize - MinBufferSize + 1) + MinBufferSize;
#endif
#ifdef ENABLE_C2BUFFER_LOG_DEBUG
        printf("#C2Buffer#Deadlock# Test#%d bufferSize=%d\n", iTest, bufferSize);
#endif //#ifdef ENABLE_C2BUFFER_LOG_DEBUG
        tester.number = 0;
        C2Buffer* c2buffer = [[C2Buffer alloc] initWithSize:bufferSize delegate:tester];
        uint8_t** destBuffers = malloc(sizeof(uint8_t*) * 2);
        int32_t** frameSizes = (int32_t**) malloc(sizeof(int32_t*) * 2);
        for (int c=0; c<2; ++c)
        {
            frameSizes[c] = (int32_t*) malloc(sizeof(int32_t) * InvokeCount);
#ifdef GIVEN_TESTCASE
            memcpy(frameSizes[c], TestCaseFrameSizes[c], sizeof(TestCaseFrameSizes[c]));
#endif
            destBuffers[c] = malloc(MaxFrameSizes[c].integerValue + 1);
            dispatch_group_async(dispatchGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                __block int32_t totalBytesRead = 0;
                destBuffers[c][0] = 0;
                for (int iCall=0; iCall<InvokeCount; ++iCall)
                {
#ifdef GIVEN_TESTCASE
                    int32_t frameSize = frameSizes[c][iCall];
#else
                    int32_t frameSize = (int32_t)lrand48() % (MaxFrameSizes[c].intValue - MinFrameSizes[c].intValue + 1) + MinFrameSizes[c].intValue;
                    frameSizes[c][iCall] = frameSize;
#endif
                    [c2buffer readBytesForConsumer:c into:&destBuffers[c][1] length:frameSize isFinal:(iCall == InvokeCount - 1) completion:^(int32_t bytesRead) {
//                        NSLog(@"#C2Buffer# Test#%d Consumer#%d Block#%d, bytesRead = %d", iTest, c, iCall, bytesRead);
                        BOOL passed = YES;
                        for (int32_t i=0; i<bytesRead-1; ++i)
                        {
                            if (destBuffers[c][i] + 1 != destBuffers[c][i+1] && (destBuffers[c][i] != 255 || destBuffers[c][i+1] != 0))
                            {
                                passed = NO;
                                printf("#C2Buffer# Test#%d Consumer#%d Block#%d Error at byte #%d(0x%x) and #%d(0x%x)\n", iTest, c, iCall, totalBytesRead + i, destBuffers[c][i], totalBytesRead + i + 1, destBuffers[c][i+1]);
                                printf("#C2Buffer#Error# bufferSize=%d\n", bufferSize);
                                for (int j=0; j<2; ++j)
                                {
                                    printf("frameSizes[%d]={", j);
                                    for (int k=0; k<InvokeCount; ++k)
                                    {
                                        printf("%d, ", frameSizes[j][k]);
                                    }
                                    printf("}\n");
                                }
                                break;
                            }
                        }
                        totalBytesRead += bytesRead;
                        destBuffers[c][0] = destBuffers[c][frameSize];
//                        if (passed)
//                            NSLog(@"#C2Buffer# Passed : Test#%d Consumer#%d Block#%d", iTest, c, iCall);
                    }];
                }
            });
        }
        dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
        for (int c=0; c<2; ++c)
        {
            free(destBuffers[c]);
            free(frameSizes[c]);
        }
        free(frameSizes);
        free(destBuffers);
    }
}

@end
