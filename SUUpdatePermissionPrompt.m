//
//  SUUpdatePermissionPrompt.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdatePermissionPrompt.h"

#import "SUHost.h"
#import "SULog.h"
#import "SUConstants.h"

@implementation SUUpdatePermissionPrompt

static Logger *sLogger;

+(void) initialize {
    sLogger = [[Logger alloc] initWithClass:self];
}

- (BOOL)shouldAskAboutProfile
{
	return [[host objectForInfoDictionaryKey:SUEnableSystemProfilingKey] boolValue];
}

- (id)initWithHost:(SUHost *)aHost systemProfile:(NSArray *)profile delegate:(id)d
{
	self = [super initWithHost:aHost windowNibName:@"SUUpdatePermissionPrompt"];
	if (self)
	{
		host = [aHost retain];
		delegate = d;
		isShowingMoreInfo = NO;
		shouldSendProfile = [self shouldAskAboutProfile];
		systemProfileInformationArray = [profile retain];
		[self setShouldCascadeWindows:NO];
	}
	return self;
}

+ (void)promptWithHost:(SUHost *)aHost systemProfile:(NSArray *)profile delegate:(id)d
{
    [sLogger log:@"Showing update permission prompt"];
         
	// If this is a background application we need to focus it in order to bring the prompt
	// to the user's attention. Otherwise the prompt would be hidden behind other applications and
	// the user would not know why the application was paused.
	if ([aHost isBackgroundApplication])
    {
        [sLogger log:@"Is background application; give focus to alert window"];
        [NSApp activateIgnoringOtherApps:YES];
    }
	
	id prompt = [[[[self class] alloc] initWithHost:aHost systemProfile:profile delegate:d] autorelease];
	[NSApp runModalForWindow:[prompt window]];
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [host bundlePath]]; }

- (void)awakeFromNib
{
    [sLogger log:@"Awake from nib"];
    
	if (![self shouldAskAboutProfile])
	{
		NSRect frame = [[self window] frame];
		frame.size.height -= [moreInfoButton frame].size.height;
		[[self window] setFrame:frame display:YES];
	} else {
        // Set the table view's delegate so we can disable row selection.
        [profileTableView setDelegate:(id)self];
    }
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return NO; }

- (void)dealloc
{
	[host release];
	[systemProfileInformationArray release];
	[super dealloc];
}

- (NSImage *)icon
{
	return [host icon];
}

- (NSString *)promptDescription
{
	return [NSString stringWithFormat:SULocalizedString(@"Should %1$@ automatically check for updates? You can always check for updates manually from the %1$@ menu.", nil), [host name]];
}

- (IBAction)toggleMoreInfo:(id)sender
{
	[self willChangeValueForKey:@"isShowingMoreInfo"];
	isShowingMoreInfo = !isShowingMoreInfo;
	[self didChangeValueForKey:@"isShowingMoreInfo"];
    [sLogger log:@"'More info' toggled - is now %s", isShowingMoreInfo ? "true" : "false"];
	
	NSView *contentView = [[self window] contentView];
	NSRect contentViewFrame = [contentView frame];
	NSRect windowFrame = [[self window] frame];
	
	NSRect profileMoreInfoViewFrame = [moreInfoView frame];
	NSRect profileMoreInfoButtonFrame = [moreInfoButton frame];
	NSRect descriptionFrame = [descriptionTextField frame];
	
	if (isShowingMoreInfo)
	{
		// Add the subview
		contentViewFrame.size.height += profileMoreInfoViewFrame.size.height;
		profileMoreInfoViewFrame.origin.y = profileMoreInfoButtonFrame.origin.y - profileMoreInfoViewFrame.size.height;
		profileMoreInfoViewFrame.origin.x = descriptionFrame.origin.x;
		profileMoreInfoViewFrame.size.width = descriptionFrame.size.width;
		
		windowFrame.size.height += profileMoreInfoViewFrame.size.height;
		windowFrame.origin.y -= profileMoreInfoViewFrame.size.height;
		
		[moreInfoView setFrame:profileMoreInfoViewFrame];
		[moreInfoView setHidden:YES];
		[contentView addSubview:moreInfoView
					 positioned:NSWindowBelow
					 relativeTo:moreInfoButton];
	} else {
		// Remove the subview
		[moreInfoView setHidden:NO];
		[moreInfoView removeFromSuperview];
		contentViewFrame.size.height -= profileMoreInfoViewFrame.size.height;
		
		windowFrame.size.height -= profileMoreInfoViewFrame.size.height;
		windowFrame.origin.y += profileMoreInfoViewFrame.size.height;
	}
	[[self window] setFrame:windowFrame display:YES animate:YES];
	[contentView setFrame:contentViewFrame];
	[contentView setNeedsDisplay:YES];
	[moreInfoView setHidden:(!isShowingMoreInfo)];
}

- (IBAction)finishPrompt:(id)sender
{
    [sLogger log:@"Closing update permission prompt window"];
	if (![delegate respondsToSelector:@selector(updatePermissionPromptFinishedWithResult:)])
		[NSException raise:@"SUInvalidDelegate" format:@"SUUpdatePermissionPrompt's delegate (%@) doesn't respond to updatePermissionPromptFinishedWithResult:!", delegate];
	[host setBool:shouldSendProfile forUserDefaultsKey:SUSendProfileInfoKey];
	[delegate updatePermissionPromptFinishedWithResult:([sender tag] == 1 ? SUAutomaticallyCheck : SUDoNotAutomaticallyCheck)];
	[[self window] close];
	[NSApp stopModal];
}

@end
