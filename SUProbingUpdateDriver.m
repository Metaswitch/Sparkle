//
//  SUProbingUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUProbingUpdateDriver.h"
#import "SUUpdater.h"
#import "SULog.h"

@implementation SUProbingUpdateDriver

static Logger *sLogger;

+(void) initialize
{
    sLogger = [[Logger alloc] initWithClass:self];
}

// Stop as soon as we have an answer! Since the superclass implementations are not called, we are responsible for notifying the delegate.

- (void)didFindValidUpdate
{
	if ([[updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)])
    {
        [sLogger log:@"Calling 'didFindValidUpdate' on updater delegate"];
		[[updater delegate] updater:updater didFindValidUpdate:updateItem];
    }
    else
    {
        [sLogger log:@"WARNING: Delegate did not respond to 'didFindUpdate' - dropping update notification"];
    }
    
	[self abortUpdate];
}

- (void)didNotFindUpdate
{
	if ([[updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)])
    {
        [sLogger log:@"Calling 'didNotFindUpdate' on updater deletate"];
		[[updater delegate] updaterDidNotFindUpdate:updater];
    }
    else
    {
        [sLogger log:@"Delegate did not respond to 'didNotFindUpdate'"];
    }
    
	[self abortUpdate];
}

@end
