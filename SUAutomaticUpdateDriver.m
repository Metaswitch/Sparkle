//
//  SUAutomaticUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/6/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUAutomaticUpdateDriver.h"

#import "SUAutomaticUpdateAlert.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUConstants.h"

@implementation SUAutomaticUpdateDriver

static Logger *sLogger;

+(void) initialize {
    sLogger = [[Logger alloc] initWithClass:self];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
    [sLogger log:@"Unarchiver finished"];
	alert = [[SUAutomaticUpdateAlert alloc] initWithAppcastItem:updateItem host:host delegate:self];
	
	// If the app is a menubar app or the like, we need to focus it first and alter the
	// update prompt to behave like a normal window. Otherwise if the window were hidden
	// there may be no way for the application to be activated to make it visible again.
	if ([host isBackgroundApplication])
	{
        [sLogger log:@"Application is running in background; set update prompt to behave as a window"];
		[[alert window] setHidesOnDeactivate:NO];
		[NSApp activateIgnoringOtherApps:YES];
	}		
	
	if ([NSApp isActive])
    {
        [sLogger log:@"App is active; show update prompt"];
		[[alert window] makeKeyAndOrderFront:self];
    }
	else
    {
        [sLogger log:@"App is inactive; wait until it becomes active to show the update prompt"];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
    [sLogger log:@"App is now active; show the update prompt"];
	[[alert window] makeKeyAndOrderFront:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"NSApplicationDidBecomeActiveNotification" object:NSApp];
}

- (void)automaticUpdateAlert:(SUAutomaticUpdateAlert *)aua finishedWithChoice:(SUAutomaticInstallationChoice)choice;
{
	switch (choice)
	{
		case SUInstallNowChoice:
            [sLogger log:@"User chose to install version %@ and restart the app", [updateItem versionString]];
			[self installWithToolAndRelaunch:YES];
			break;
			
		case SUInstallLaterChoice:
            [sLogger log:@"User opted to postpone update to version %@", [updateItem versionString]];
			postponingInstallation = YES;
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
			break;

		case SUDoNotInstallChoice:
            [sLogger log:@"User opted to skip version %@", [updateItem versionString]];
			[host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
			[self abortUpdate];
			break;
	}
}

- (BOOL)shouldInstallSynchronously
{
    [sLogger log:@"Should install synchronously? %s", postponingInstallation ? "true" : "false"];
    return postponingInstallation;
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
	showErrors = YES;
	[super installWithToolAndRelaunch:relaunch];
}

- (void)applicationWillTerminate:(NSNotification *)note
{
    [sLogger log:@"Got 'applicationWillTerminate'"];
	[self installWithToolAndRelaunch:NO];
}

- (void)abortUpdateWithError:(NSError *)error
{
	if (showErrors)
    {
        [sLogger log:@"Aborting update with error %@", error];
		[super abortUpdateWithError:error];
    }
	else
    {
        [sLogger log:@"Aborting update due to error, but will not alert user. Error was %@", error];
		[self abortUpdate];
    }
}

@end
