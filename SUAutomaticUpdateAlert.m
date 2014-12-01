//
//  SUAutomaticUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/18/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUAutomaticUpdateAlert.h"
#import "SUHost.h"
#import "SULog.h"

@implementation SUAutomaticUpdateAlert

static Logger *sLogger;

+(void) initialize {
    sLogger = [[Logger alloc] initWithClass:self];
}

- (id)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost delegate:del;
{
	self = [super initWithHost:aHost windowNibName:@"SUAutomaticUpdateAlert"];
	if (self)
	{
		updateItem = [item retain];
		delegate = del;
		host = [aHost retain];
		[self setShouldCascadeWindows:NO];
		[[self window] center];
	}
	return self;
}

- (void)dealloc
{
	[host release];
	[updateItem release];
	[super dealloc];
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [host bundlePath], [host installationPath]]; }

- (IBAction)installNow:sender
{
    [sLogger log:@"User clicked 'install now'"];
	[self close];
	[delegate automaticUpdateAlert:self finishedWithChoice:SUInstallNowChoice];
}

- (IBAction)installLater:sender
{
    [sLogger log:@"User clicked 'remind me later'"];
	[self close];
	[delegate automaticUpdateAlert:self finishedWithChoice:SUInstallLaterChoice];
}

- (IBAction)doNotInstall:sender
{
    [sLogger log:@"User clicked 'skip this update'"];
	[self close];
	[delegate automaticUpdateAlert:self finishedWithChoice:SUDoNotInstallChoice];
}

- (NSImage *)applicationIcon
{
	return [host icon];
}

- (NSString *)titleText
{
	return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ is ready to install!", nil), [host name]];
}

- (NSString *)descriptionText
{
	return [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been downloaded and is ready to use! Would you like to install it and relaunch %1$@ now?", nil), [host name], [updateItem displayVersionString]];
}

@end
