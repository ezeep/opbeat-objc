//
//  OpbeatClient.h
//  opbeat-objc
//
//  Created by Marian Zange on 2/8/14.
//  Copyright (c) 2014 ezeep GmbH. All rights reserved.
//
//  opbeat-objc is based on the excellent raven-objc
//  Copyright (c) 2012 Kevin Renskers
//
                                 
#import <Foundation/Foundation.h>

#define OpbeatCaptureMessage( s, ... ) [[OpbeatClient sharedClient] captureMessage:[NSString stringWithFormat:(s), ##__VA_ARGS__] level:kOpbeatLogLevelDebugInfo method:__FUNCTION__ file:__FILE__ line:__LINE__]

typedef enum {
    kOpbeatLogLevelDebug,
    kOpbeatLogLevelDebugInfo,
    kOpbeatLogLevelDebugWarning,
    kOpbeatLogLevelDebugError,
    kOpbeatLogLevelDebugFatal
} OpbeatLogLevel;

@interface OpbeatClient : NSObject <NSURLConnectionDelegate>

+ (OpbeatClient *)sharedClient;
+ (OpbeatClient *)clientWithEndpoint:(NSString *)endpoint token:(NSString *)token;

// Messages
- (void)captureMessage:(NSString *)message;
- (void)captureMessage:(NSString *)message level:(OpbeatLogLevel)level;
- (void)captureMessage:(NSString *)message level:(OpbeatLogLevel)level method:(const char *)method file:(const char *)file line:(NSInteger)line;

// Exceptions
- (void)captureException:(NSException *)exception;
- (void)captureException:(NSException *)exception sendNow:(BOOL)sendNow;
- (void)setupExceptionHandler;

@end
