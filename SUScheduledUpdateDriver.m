//
//  SUScheduledUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/6/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUScheduledUpdateDriver.h"
#import "SUUpdater.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SULog.h"
#import "SUVersionComparisonProtocol.h"

@implementation SUScheduledUpdateDriver

static Logger *sLogger;

+(void) initialize {
    sLogger = [[Logger alloc] initWithClass:self];
}

- (void)didFindValidUpdate
{
    [sLogger log:@"Found valid update"];
	showErrors = YES; // We only start showing errors after we present the UI for the first time.
	[super didFindValidUpdate];
}

- (void)didNotFindUpdate
{
	if ([[updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)])
    {
        [sLogger log:@"Calling updaterDidNotFindUpdate on updater delegate"];
		[[updater delegate] updaterDidNotFindUpdate:updater];
    }
    
    // Don't tell the user that no update was found; this was a scheduled update.
    [sLogger log:@"Did not find an update; user will not be notified"];
	[self abortUpdate];
}

- (void)abortUpdateWithError:(NSError *)error
{
	if (showErrors)
    {
        [sLogger log:@"Aborting upgrade due to error: ", error];
		[super abortUpdateWithError:error];
    }
	else
    {
        [sLogger log:@"Aborting upgrade due to error, but will not notify user. Error was: ", error];
		[self abortUpdate];
    }
}

@end
