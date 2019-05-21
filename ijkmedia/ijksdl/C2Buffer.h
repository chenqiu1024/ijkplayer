//
//  C2Buffer.h
//  LeetCodePlayground
//
//  Buffer with 2 consumers
//
//  Created by DOM QIU on 2019/5/11.
//  Copyright © 2019 Cyllenge. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol C2BufferDelegate <NSObject>

@required
-(int32_t) c2BufferFillDataTo:(void*)buffer length:(int32_t)length;

@end

@interface C2Buffer : NSObject

@property (nonatomic, strong) __nonnull id<C2BufferDelegate> delegate;

-(instancetype) initWithSize:(int32_t)size delegate:(_Nonnull id<C2BufferDelegate>)delegate;

-(void) notifyConsumerWillDeactive:(int)consumerIndex;

-(int32_t) readBytesForConsumer:(int)consumerIndex into:(void*)destBuffer length:(int32_t)length isFinal:(BOOL)isFinal completion:(void(^)(int32_t))completion;

-(void) finish;

@end


@interface C2BufferTest : NSObject

+(void) test;

@end

NS_ASSUME_NONNULL_END
