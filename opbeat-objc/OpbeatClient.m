//
//  OpbeatClient.m
//  opbeat-objc
//
//  Created by Marian Zange on 2/8/14.
//  Copyright (c) 2014 ezeep GmbH. All rights reserved.
//
//  opbeat-objc is based on the excellent raven-objc
//  Copyright (c) 2012 Kevin Renskers
//

#import "OpbeatClient.h"
#import "OpbeatConfig.h"
#import "RavenJSONUtilities.h"

@interface OpbeatClient ()

@property (strong, nonatomic) NSDateFormatter *dateFormatter;
@property (strong, nonatomic) NSMutableData *receivedData;
@property (strong, nonatomic) OpbeatConfig *config;

- (void)sendDictionary:(NSDictionary *)dict;
- (void)sendJSON:(NSData *)JSON;

@end

NSString *const kOpbeatLogLevelArray[] = {
    @"debug",
    @"info",
    @"warning",
    @"error",
    @"fatal"
};

NSString *const userDefaultsKey = @"com.ezeep.OpbeatClient.Exceptions";
NSString *const opbeatClient = @"opbeat-objc/0.1";

static OpbeatClient *sharedClient = nil;

@implementation OpbeatClient

+ (OpbeatClient *)sharedClient {
    return sharedClient;
}

+ (OpbeatClient *)clientWithEndpoint:(NSString *)endpoint token:(NSString *)token {
    return [[self alloc] initWithEndpoint:endpoint token:token];
}

- (id)initWithEndpoint:(NSString *)endpoint token:(NSString *)token {
    self = [super init];
    if (self) {
        if (!endpoint || !token) return nil;
        
        self.config = [[OpbeatConfig alloc] init];
        self.config.endpoint = [NSURL URLWithString:endpoint];
        self.config.token = token;

        if (sharedClient == nil) {
            sharedClient = self;
        }
    }
    return self;
}


- (NSDateFormatter *)dateFormatter {
    if (!_dateFormatter) {
        NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setTimeZone:timeZone];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];
    }
    
    return _dateFormatter;
}

- (void)setupExceptionHandler {
    NSSetUncaughtExceptionHandler(&exceptionHandler);
    
    // Process saved crash reports
    NSArray *reports = [[NSUserDefaults standardUserDefaults] objectForKey:userDefaultsKey];
    if (reports != nil && [reports count]) {
        for (NSDictionary *data in reports) {
            [self sendDictionary:data];
        }
        [[NSUserDefaults standardUserDefaults] setObject:[NSArray array] forKey:userDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

void exceptionHandler(NSException *exception) {
	[[OpbeatClient sharedClient] captureException:exception sendNow:NO];
}

- (void)captureException:(NSException *)exception {
    [self captureException:exception sendNow:YES];
}

- (void)captureException:(NSException *)exception sendNow:(BOOL)sendNow {
    NSString *message = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
    
    NSDictionary *exceptionDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   exception.name, @"type",
                                   exception.reason, @"value",
                                   nil];
    
    NSArray *callStack = [exception callStackSymbols];
    
    NSMutableArray *stacktrace = [[NSMutableArray alloc] initWithCapacity:[callStack count]];

    NSString *framePattern = @"\\d+\\s+([^\\s]+)\\s+([^\\+]+)\\s[^\\w]+(\\d+)";
    NSRegularExpression *frameRegex = [NSRegularExpression regularExpressionWithPattern: framePattern options:0 error:nil];

    for (NSString *call in callStack) {
        NSRange range = NSMakeRange(0, [call length]);
        NSArray *matches = [frameRegex matchesInString:call options:0 range:range];
        NSRange cls = [[matches objectAtIndex:0] rangeAtIndex:1];
        NSRange func = [[matches objectAtIndex:0] rangeAtIndex:2];
        NSRange line = [[matches objectAtIndex:0] rangeAtIndex:3];
        
        [stacktrace addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                               [call substringWithRange:func], @"function",
                               [call substringWithRange:cls], @"filename",
                               [call substringWithRange:line], @"lineno",
                               nil]];
    }
    
    NSString *culpritPattern = @"-\\[([^\\]+]+)";
    NSRegularExpression *culpritRegex = [NSRegularExpression regularExpressionWithPattern: culpritPattern options:0 error:nil];
    NSRange range = NSMakeRange(0, [exception.reason length]);
    NSArray *matches = [culpritRegex matchesInString:exception.reason options:0 range:range];
    NSRange culprit = [[matches objectAtIndex:0] rangeAtIndex:1];
    
    NSDictionary *data = [self prepareDictionaryForMessage:message
                                                     level:kOpbeatLogLevelDebugFatal
                                                   culprit:([matches count] > 0) ? [exception.reason substringWithRange:culprit] : nil
                                                stacktrace:stacktrace
                                                 exception:exceptionDict];
    
    if (!sendNow) {
        // We can't send this exception to Sentry now, e.g. because the app is killed before the
        // connection can be made. So, save it into NSUserDefaults.
        NSArray *reports = [[NSUserDefaults standardUserDefaults] objectForKey:userDefaultsKey];
        if (reports != nil) {
            NSMutableArray *reportsCopy = [reports mutableCopy];
            [reportsCopy addObject:data];
            [[NSUserDefaults standardUserDefaults] setObject:reportsCopy forKey:userDefaultsKey];
        } else {
            reports = [NSArray arrayWithObject:data];
            [[NSUserDefaults standardUserDefaults] setObject:reports forKey:userDefaultsKey];
        }
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        [self sendDictionary:data];
    }
}

#pragma mark - Private methods

- (NSDictionary *)prepareDictionaryForMessage:(NSString *)message
                                        level:(OpbeatLogLevel)level
                                      culprit:(NSString *)culprit
                                   stacktrace:(NSArray *)stacktrace
                                    exception:(NSDictionary *)exceptionDict {
    NSDictionary *stacktraceDict = [NSDictionary dictionaryWithObjectsAndKeys:stacktrace, @"frames", nil];
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                          [self.dateFormatter stringFromDate:[NSDate date]], @"timestamp",
                          kOpbeatLogLevelArray[level], @"level",
                          message, @"message",
                          culprit ?: @"", @"culprit",
                          stacktraceDict, @"stacktrace",
                          exceptionDict, @"exception",
                          nil];
    
    return dict;
}

- (void)sendDictionary:(NSDictionary *)dict {
    NSError *error = nil;
    NSData *JSON = JSONEncode(dict, &error);

    [self sendJSON:JSON];
}

- (void)sendJSON:(NSData *)JSON {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.config.endpoint];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"Bearer f10a74b24dfb9878289daa3432b4dfbc477db020" forHTTPHeaderField:@"Authorization"];
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[JSON length]] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody:JSON];

    NSURLConnection *connection = [NSURLConnection connectionWithRequest:request delegate:self];
    if (connection) {
        self.receivedData = [NSMutableData data];
    }
}

#pragma mark - Messages

- (void)captureMessage:(NSString *)message {
    [self captureMessage:message level:kOpbeatLogLevelDebugInfo];
}

- (void)captureMessage:(NSString *)message level:(OpbeatLogLevel)level {
    [self captureMessage:message level:level method:nil file:nil line:0];
}

- (void)captureMessage:(NSString *)message level:(OpbeatLogLevel)level method:(const char *)method file:(const char *)file line:(NSInteger)line {
    NSArray *stacktrace;
    if (method && file && line) {
        NSDictionary *frame = [NSDictionary dictionaryWithObjectsAndKeys:
                               [[NSString stringWithUTF8String:file] lastPathComponent], @"filename",
                               [NSString stringWithUTF8String:method], @"function",
                               [NSNumber numberWithInt:line], @"lineno",
                               nil];
        
        stacktrace = [NSArray arrayWithObject:frame];
    }
    
    NSDictionary *data = [self prepareDictionaryForMessage:message
                                                     level:level
                                                   culprit:file ? [NSString stringWithUTF8String:file] : nil
                                                stacktrace:stacktrace
                                                 exception:nil];

    [self sendDictionary:data];
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.receivedData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSLog(@"Connection failed! Error - %@ %@", [error localizedDescription], [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey]);
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    NSLog(@"Report sent to Opbeat");
}


@end
