//
//  SUUIBasedUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/5/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUIBasedUpdateDriver.h"

#import "SUUpdateAlert.h"
#import "SUUpdater_Private.h"
#import "SUHost.h"
#import "SUStatusController.h"
#import "SUConstants.h"
#import "SUPasswordPrompt.h"
#import "SULog.h"

#pragma GCC diagnostic ignored "-Wformat-security"

@implementation SUUIBasedUpdateDriver

static Logger *sLogger;

+(void) initialize {
    sLogger = [[Logger alloc] initWithClass:self];
}

- (void)didFindValidUpdate
{
	updateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:updateItem isRequired:[self itemContainsRequiredUpdate:updateItem] host:host];
	[updateAlert setDelegate:self];
	
	id<SUVersionDisplay>	versDisp = nil;
    if ([[updater delegate] respondsToSelector:@selector(versionDisplayerForUpdater:)]) {
		versDisp = [[updater delegate] versionDisplayerForUpdater: updater];
        if (versDisp) {
            [sLogger log:@"Updater delegate provided a version displayer"];
        }
    }
	[updateAlert setVersionDisplayer: versDisp];
	
	if ([[updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)])
    {
        [sLogger log:@"Invokind didFindValidUpdate on updater delegate"];
		[[updater delegate] updater:updater didFindValidUpdate:updateItem];
    }

	// If the app is a menubar app or the like, we need to focus it first and alter the
	// update prompt to behave like a normal window. Otherwise if the window were hidden
	// there may be no way for the application to be activated to make it visible again.
	if ([host isBackgroundApplication])
	{
        [sLogger log:@"Host is a background application; make update prompt behave like a normal window"];
		[[updateAlert window] setHidesOnDeactivate:NO];
		[NSApp activateIgnoringOtherApps:YES];
	}
	
	// Only show the update alert if the app is active; otherwise, we'll wait until it is.
	if ([NSApp isActive])
  {
    // TODO: Make the window modal so users can't ignore a required update.  If the code below is commented back in, the window is modal, but cannot be closed.
    //[NSApp runModalForWindow:[updateAlert window]];
      [sLogger log:@"Make update alert window visible"];
		[[updateAlert window] makeKeyAndOrderFront:self];
  }
	else
    {
        [sLogger log:@"Application is not active; don't show the update prompt now. Wait until it becomes active."];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
    }
}

- (void)didNotFindUpdate
{
	if ([[updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)])
    {
        [sLogger log:@"Calling updater delegate updaterDidNotFindUpdate method"];
		[[updater delegate] updaterDidNotFindUpdate:updater];
    }
	
    [sLogger log:@"No update found. Tell the user the app is up to date."];
	NSAlert *alert = [NSAlert alertWithMessageText:SULocalizedString(@"You're up-to-date!", nil) defaultButton:SULocalizedString(@"OK", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [host name], [host displayVersion]];
	[self showModalAlert:alert];
	[self abortUpdate];
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
  // TODO: Make the window modal so users can't ignore a required update.  If the code below is commented back in, the window is modal, but cannot be closed.
  //[NSApp runModalForWindow:[updateAlert window]];
    [sLogger log:@"Application just became active. Show the update prompt."];
	[[updateAlert window] makeKeyAndOrderFront:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"NSApplicationDidBecomeActiveNotification" object:NSApp];
}

- (void)updateAlert:(SUUpdateAlert *)alert finishedWithChoice:(SUUpdateAlertChoice)choice
{
	[updateAlert release]; updateAlert = nil;
	[host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
	switch (choice)
	{
		case SUInstallUpdateChoice:
            [sLogger log:@"User elected to install update %@", [updateItem versionString]];
			statusController = [[SUStatusController alloc] initWithHost:host];
			[statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
			[statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
			[statusController showWindow:self];	
			[self downloadUpdate];
			break;
		
		case SUOpenInfoURLChoice:
            [sLogger log:@"User elected to show the update info window for %@", [updateItem versionString]];
			[[NSWorkspace sharedWorkspace] openURL: [updateItem infoURL]];
			[self abortUpdate];
			break;
		
		case SUSkipThisVersionChoice:
            [sLogger log:@"User elected to skip update %@", [updateItem versionString]];
			[host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
			[self abortUpdate];
			break;
			
		case SURemindMeLaterChoice:
            [sLogger log:@"User said 'remind me later'"];
			[self abortUpdate];
			break;			
	}			
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response
{
	[statusController setMaxProgressValue:[response expectedContentLength]];
}

- (NSString *)humanReadableSizeFromDouble:(double)value
{
	if (value < 1000)
		return [NSString stringWithFormat:@"%.0lf %@", value, SULocalizedString(@"B", @"the unit for bytes")];
	
	if (value < 1000 * 1000)
		return [NSString stringWithFormat:@"%.0lf %@", value / 1000.0, SULocalizedString(@"KB", @"the unit for kilobytes")];
	
	if (value < 1000 * 1000 * 1000)
		return [NSString stringWithFormat:@"%.1lf %@", value / 1000.0 / 1000.0, SULocalizedString(@"MB", @"the unit for megabytes")];
	
	return [NSString stringWithFormat:@"%.2lf %@", value / 1000.0 / 1000.0 / 1000.0, SULocalizedString(@"GB", @"the unit for gigabytes")];	
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
	[statusController setProgressValue:[statusController progressValue] + (double)length];
	if ([statusController maxProgressValue] > 0.0)
		[statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ of %@", nil), [self humanReadableSizeFromDouble:[statusController progressValue]], [self humanReadableSizeFromDouble:[statusController maxProgressValue]]]];
	else
		[statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ downloaded", nil), [self humanReadableSizeFromDouble:[statusController progressValue]]]];
}

- (IBAction)cancelDownload: (id)sender
{
    [sLogger log:@"User cancelled the update download"];
	if (download)
		[download cancel];
	[self abortUpdate];
}

- (void)extractUpdate
{
	// Now we have to extract the downloaded archive.
    [sLogger log:@"Extracting update..."];
	[statusController beginActionWithTitle:SULocalizedString(@"Extracting update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
	[statusController setButtonEnabled:NO];
	[super extractUpdate];
}

- (void)unarchiver:(SUUnarchiver *)ua extractedLength:(unsigned long)length
{
	// We do this here instead of in extractUpdate so that we only have a determinate progress bar for archives with progress.
	if ([statusController maxProgressValue] == 0.0)
	{
		NSDictionary * attributes;
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
		attributes = [[NSFileManager defaultManager] fileAttributesAtPath:downloadPath traverseLink:NO];
#else
		attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:downloadPath error:nil];
#endif
		[statusController setMaxProgressValue:[[attributes objectForKey:NSFileSize] doubleValue]];
	}
	[statusController setProgressValue:[statusController progressValue] + (double)length];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
    [sLogger log:@"Unarchiver finished - notify usert the upgrade is ready to install"];
	[statusController beginActionWithTitle:SULocalizedString(@"Ready to Install", nil) maxProgressValue:1.0 statusText:nil];
	[statusController setProgressValue:1.0]; // Fill the bar.
	[statusController setButtonEnabled:YES];
	[statusController setButtonTitle:SULocalizedString(@"Install and Relaunch", nil) target:self action:@selector(installAndRestart:) isDefault:YES];
	[[statusController window] makeKeyAndOrderFront: self];
	[NSApp requestUserAttention:NSInformationalRequest];	
}

- (void)unarchiver:(SUUnarchiver *)unarchiver requiresPasswordReturnedViaInvocation:(NSInvocation *)invocation
{
    [sLogger log:@"Update requires password"];
    SUPasswordPrompt *prompt = [[SUPasswordPrompt alloc] initWithHost:host];
    NSString *password = nil;
    if([prompt run]) 
    {
        password = [prompt password];
    }
    [prompt release];
    [invocation setArgument:&password atIndex:2];
    [invocation invoke];
}

- (void)installAndRestart: (id)sender
{
    [sLogger log:@"Will install upgrade and restart..."];
    [self installWithToolAndRelaunch:YES];
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
	[statusController beginActionWithTitle:SULocalizedString(@"Installing update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
	[statusController setButtonEnabled:NO];
	[super installWithToolAndRelaunch:relaunch];
	
	
	// if a user chooses to NOT relaunch the app (as is the case with WebKit
	// when it asks you if you are sure you want to close the app with multiple
	// tabs open), the status window still stays on the screen and obscures
	// other windows; with this fix, it doesn't
	
	if (statusController)
	{
		[statusController close];
		[statusController autorelease];
		statusController = nil;
	}
}

- (void)abortUpdateWithError:(NSError *)error
{
    [sLogger log:@"Update aborted with error: %@", error];
	NSAlert *alert = [NSAlert alertWithMessageText:SULocalizedString(@"Update Error!", nil) defaultButton:SULocalizedString(@"Cancel Update", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:[error localizedDescription]];
	[self showModalAlert:alert];
	[super abortUpdateWithError:error];
}

- (void)abortUpdate
{
    [sLogger log:@"Update aborted"];
	if (statusController)
	{
		[statusController close];
		[statusController autorelease];
		statusController = nil;
	}
	[super abortUpdate];
}

- (void)showModalAlert:(NSAlert *)alert
{
	if ([[updater delegate] respondsToSelector:@selector(updaterWillShowModalAlert:)])
		[[updater delegate] updaterWillShowModalAlert: updater];

	// When showing a modal alert we need to ensure that background applications
	// are focused to inform the user since there is no dock icon to notify them.
	if ([host isBackgroundApplication]) { [NSApp activateIgnoringOtherApps:YES]; }
	
	[alert setIcon:[host icon]];
	[alert runModal];
	
	if ([[updater delegate] respondsToSelector:@selector(updaterDidShowModalAlert:)])
		[[updater delegate] updaterDidShowModalAlert: updater];
}

@end
