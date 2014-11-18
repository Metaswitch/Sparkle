//
//  SUUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdateDriver.h"
#import "SUHost.h"
#import "SULog.h"

NSString * const SUUpdateDriverFinishedNotification = @"SUUpdateDriverFinished";

@implementation SUUpdateDriver

static Logger *sLogger;

+(void) initialize {
    sLogger = [[Logger alloc] initWithClass:self];
}

- initWithUpdater:(SUUpdater *)anUpdater
{
	if ((self = [super init]))
		updater = anUpdater;
	return self;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [host bundlePath], [host installationPath]]; }

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)h
{
    [sLogger log:@"Will check for updates at %@; host is %@ <%@,%@>", URL, h, [h bundlePath], [h installationPath]];
	appcastURL = [URL copy];
	host = [h retain];
}

- (void)abortUpdate
{
    [sLogger log:@"Update aborted"];
	[self setValue:[NSNumber numberWithBool:YES] forKey:@"finished"];	
	[[NSNotificationCenter defaultCenter] postNotificationName:SUUpdateDriverFinishedNotification object:self];
}

- (BOOL)finished { return finished; }

- (void)dealloc
{
    [host release];
	[appcastURL release];
    [super dealloc];
}

- (SUHost*)host
{
    return host;
}

- (void)setHost:(SUHost*)newHost
{
    [sLogger log:@"Set new host: %@ <%@,%@>", newHost, [newHost bundlePath], [new installation]]
    [host release];
    host = [newHost retain];
}

@end
