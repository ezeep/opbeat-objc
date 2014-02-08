//
//  OpbeatConfig.h
//  opbeat-objc
//
//  Created by Marian Zange on 2/8/14.
//  Copyright (c) 2014 ezeep GmbH. All rights reserved.
//
//  opbeat-objc is based on the excellent raven-objc
//  Copyright (c) 2012 Kevin Renskers
//

#import <Foundation/Foundation.h>

@interface OpbeatConfig : NSObject

@property (strong, nonatomic) NSURL *endpoint;
@property (strong, nonatomic) NSString *token;

@end
