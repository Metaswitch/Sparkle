//
//  SUUserInitiatedUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/30/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUserInitiatedUpdateDriver.h"

#import "SUStatusController.h"
#import "SUHost.h"
#import "SULog.h"


@implementation SUUserInitiatedUpdateDriver

static Logger *sLogger;

+(void) initialize
{
    sLogger = [[Logger alloc] initWithClass:self];
}

- (void)closeCheckingWindow
{
	if (checkingController)
	{
        [sLogger log:@"Closing 'checking for updates' window"];
		[[checkingController window] close];
		[checkingController release];
		checkingController = nil;
	}
    else
    {
        [sLogger log:@"WARNING: Could not close 'checking for updates' window, as we have no reference to it"];
    }
}

- (void)cancelCheckForUpdates:sender
{
    [sLogger log:@"Cancel check for updates"];
	[self closeCheckingWindow];
	isCanceled = YES;
}

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
    [sLogger log:@"Check for updates at URL %@", URL];
	checkingController = [[SUStatusController alloc] initWithHost:aHost];
	[[checkingController window] center]; // Force the checking controller to load its window.
	[checkingController beginActionWithTitle:SULocalizedString(@"Checking for updates...", nil) maxProgressValue:0.0 statusText:nil];
	[checkingController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelCheckForUpdates:) isDefault:NO];
	[checkingController showWindow:self];
	[super checkForUpdatesAtURL:URL host:aHost];
	
	// For background applications, obtain focus.
	// Useful if the update check is requested from another app like System Preferences.
	if ([aHost isBackgroundApplication])
	{
        [sLogger log:@"We are a background application; request focus"];
		[NSApp activateIgnoringOtherApps:YES];
	}
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
	if (isCanceled)
	{
        [sLogger log:@"Appcast finished loading; but we're cancelled, so just abort"];
		[self abortUpdate];
		return;
	}
         
    [sLogger log:@"Appcast finished loading"];
	[self closeCheckingWindow];
	[super appcastDidFinishLoading:ac];
}

- (void)abortUpdateWithError:(NSError *)error
{
	[self closeCheckingWindow];
	[super abortUpdateWithError:error];
}

- (void)abortUpdate
{
	[self closeCheckingWindow];
	[super abortUpdate];
}

- (void)appcast:(SUAppcast *)ac failedToLoadWithError:(NSError *)error
{
	if (isCanceled)
	{
        [sLogger log:@"Appcast failed to load; but we've already been cancelled, so just ignore it. Error was: %@", error];
		[self abortUpdate];
		return;
	}
    
    [sLogger log:@"WARNING: Appcast failed to load: %@", error];
	[super appcast:ac failedToLoadWithError:error];
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
    BOOL bHostSupportsItem = [self hostSupportsItem:ui];
    BOOL bIsItemNewer = [self isItemNewer:ui];
    BOOL result = bHostSupportsItem && bIsItemNewer;
    
	// We don't check to see if this update's been skipped, because the user explicitly *asked* if he had the latest version.
    [sLogger log:@"Item <Title:%@, Version:%@, URL:%@> contains valid update? %@ (hostSupportsItem? %@, isItemNewer? %@)",
     [ui title], [ui versionString], [ui fileURL],
     result ? "true" : "false",
     bHostSupportsItem ? "true" : "false",
     bIsItemNewer ? "true" : "false"];

    return result;
}

@end
