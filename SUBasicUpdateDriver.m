//
//  SUBasicUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUBasicUpdateDriver.h"

#import "SUHost.h"
#import "SUDSAVerifier.h"
#import "SUInstaller.h"
#import "SUStandardVersionComparator.h"
#import "SUUnarchiver.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUPlainInstaller.h"
#import "SUPlainInstallerInternals.h"
#import "SUBinaryDeltaCommon.h"
#import "SUCodeSigningVerifier.h"
#import "SUUpdater_Private.h"

@interface SUBasicUpdateDriver () <NSURLDownloadDelegate>; @end


@implementation SUBasicUpdateDriver

static Logger *sLogger;

+(void) initialize {
    sLogger = [[Logger alloc] initWithClass:self];
}

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
	[super checkForUpdatesAtURL:URL host:aHost];
	if ([aHost isRunningOnReadOnlyVolume])
	{
        [sLogger log:@"ERROR: Update failure - running from a read-only disc"];
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated when it's running from a read-only volume like a disk image or an optical drive. Move %1$@ to your Applications folder, relaunch it from there, and try again.", nil), [aHost name]] forKey:NSLocalizedDescriptionKey]]];
		return;
	}	
	
	SUAppcast *appcast = [[SUAppcast alloc] init];
	CFRetain(appcast); // We'll manage the appcast's memory ourselves so we don't have to make it an IV to support GC.
	[appcast release];
	
	[appcast setDelegate:self];
	[appcast setUserAgentString:[updater userAgentString]];
    [sLogger log:@"User agent string is %@", [updater userAgentString]];
	[appcast fetchAppcastFromURL:URL];
}

- (id <SUVersionComparison>)versionComparator
{
	id <SUVersionComparison> comparator = nil;
	
	// Give the delegate a chance to provide a custom version comparator
	if ([[updater delegate] respondsToSelector:@selector(versionComparatorForUpdater:)])
    {
        [sLogger log:@"Updater delegate will handle version comparison"];
		comparator = [[updater delegate] versionComparatorForUpdater:updater];
    }
	
	// If we don't get a comparator from the delegate, use the default comparator
	if (!comparator)
    {
        [sLogger log:@"Will use default comparator for version check"];
		comparator = [SUStandardVersionComparator defaultComparator];
    }
	
	return comparator;
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui
{
	return [[self versionComparator] compareVersion:[host version] toVersion:[ui versionString]] == NSOrderedAscending;
}

- (BOOL)hostSupportsItem:(SUAppcastItem *)ui
{
	if (([ui minimumSystemVersion] == nil || [[ui minimumSystemVersion] isEqualToString:@""]) && 
        ([ui maximumSystemVersion] == nil || [[ui maximumSystemVersion] isEqualToString:@""])) { return YES; }
    
    BOOL minimumVersionOK = TRUE;
    BOOL maximumVersionOK = TRUE;
    
    // Check minimum and maximum System Version
    if ([ui minimumSystemVersion] != nil && ![[ui minimumSystemVersion] isEqualToString:@""]) {
        minimumVersionOK = [[SUStandardVersionComparator defaultComparator] compareVersion:[ui minimumSystemVersion] toVersion:[SUHost systemVersionString]] != NSOrderedDescending;
    }
    if ([ui maximumSystemVersion] != nil && ![[ui maximumSystemVersion] isEqualToString:@""]) {
        maximumVersionOK = [[SUStandardVersionComparator defaultComparator] compareVersion:[ui maximumSystemVersion] toVersion:[SUHost systemVersionString]] != NSOrderedAscending;
    }
    
    return minimumVersionOK && maximumVersionOK;
}

- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui
{
	NSString *skippedVersion = [host objectForUserDefaultsKey:SUSkippedVersionKey];
	if (skippedVersion == nil) { return NO; }
	return [[self versionComparator] compareVersion:[ui versionString] toVersion:skippedVersion] != NSOrderedDescending;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
	return [self hostSupportsItem:ui] && [self isItemNewer:ui] && ![self itemContainsSkippedVersion:ui];
}

- (BOOL)itemContainsRequiredUpdate:(SUAppcastItem *)ui
{
    NSString *minimumHostVersion = [[[ui propertiesDictionary] objectForKey:@"enclosure"] objectForKey:@"sparkle:requiredVersion"];
    return [[self versionComparator] compareVersion:[host version] toVersion:minimumHostVersion] == NSOrderedAscending;
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
    [sLogger log:@"Entering appcastDidFinishLoading"];
    
	if ([[updater delegate] respondsToSelector:@selector(updater:didFinishLoadingAppcast:)])
    {
        [sLogger log:@"Calling didFinishLoadingAppcast on updater delegate"];
		[[updater delegate] updater:updater didFinishLoadingAppcast:ac];
    }
    
    SUAppcastItem *item = nil;
    
	// Now we have to find the best valid update in the appcast.
	if ([[updater delegate] respondsToSelector:@selector(bestValidUpdateInAppcast:forUpdater:)]) // Does the delegate want to handle it?
	{
		item = [[updater delegate] bestValidUpdateInAppcast:ac forUpdater:updater];
        if (item != nil)
        {
            [sLogger log:@"Updater delegate chose a best valid update: <Title: '%@', Version: '%@', URL: '%@'>",
             [item title],
             [item versionString],
             [item fileURL]];
        }
        [sLogger log:@"Updater delegate returned a nil value for best valid update"];
	}
	else // If not, we'll take care of it ourselves.
	{
		// Find the first update we can actually use.
		NSEnumerator *updateEnumerator = [[ac items] objectEnumerator];
		do {
			item = [updateEnumerator nextObject];
            if (item != nil)
            {
                [sLogger log:@"Considering update: <Title: '%@', Version: '%@', URL: '%@'>",
                 [item title],
                 [item versionString],
                 [item fileURL]];
            }
		} while (item && ![self hostSupportsItem:item]);

        if (item != nil)
        {
            [sLogger log:@"Chose best valid update: <Title: '%@', Version: '%@', URL: '%@'>",
             [item title],
             [item versionString],
             [item fileURL]];
        }
        else
        {
            [sLogger log:@"Chose value 'nil' for best valid update."];
        }
        
		if (binaryDeltaSupported()) {
            [sLogger log:@"Binary deltas are supported - do we have one?"];
			SUAppcastItem *deltaUpdateItem = [[item deltaUpdates] objectForKey:[host version]];
			if (deltaUpdateItem && [self hostSupportsItem:deltaUpdateItem]) {
				nonDeltaUpdateItem = [item retain];
				item = deltaUpdateItem;
                [sLogger log:@"Using delta update: <Title: '%@', Version: '%@', URL: '%@'>",
                 [item title],
                 [item versionString],
                 [item fileURL]];
			}
            else
            {
                [sLogger log:@"No delta available for this update."];
            }
		}
	}
    
    updateItem = [item retain];
	if (ac) { CFRelease(ac); } // Remember that we're explicitly managing the memory of the appcast.
	if (updateItem == nil)
    {
        [sLogger log:@"updateItem was nil - no update found"];
        [self didNotFindUpdate];
        return;
    }
	
	if ([self itemContainsValidUpdate:updateItem])
    {
        [sLogger log:@"Update appears valid"];
		[self didFindValidUpdate];
    }
	else
    {
        [sLogger log:@"WARNING: Update is invalid - will not update"];
		[self didNotFindUpdate];
    }
}

- (void)appcast:(SUAppcast *)ac failedToLoadWithError:(NSError *)error
{
	if (ac) { CFRelease(ac); } // Remember that we're explicitly managing the memory of the appcast.
	[self abortUpdateWithError:error];
}

- (void)didFindValidUpdate
{
    [sLogger log:@"Valid update found: <Title: '%@', Version: '%@', URL: '%@'>",
     [updateItem title],
     [updateItem versionString],
     [updateItem fileURL]];
    
	if ([[updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)])
    {
        [sLogger log:@"Invoking didFindValidUpdate on delegate"];
		[[updater delegate] updater:updater didFindValidUpdate:updateItem];
    }
    
	[self downloadUpdate];
}

- (void)didNotFindUpdate
{
    [sLogger log:@"No valid update found"];
	if ([[updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)])
    {
        [sLogger log:@"Invoking updaterDidNotFindUpdate on updater delegate"];
		[[updater delegate] updaterDidNotFindUpdate:updater];
    }
    
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUNoUpdateError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:SULocalizedString(@"You already have the newest version of %@.", nil), [host name]] forKey:NSLocalizedDescriptionKey]]];
}

- (void)downloadUpdate
{
    [sLogger log:@"Will download update from: %@", [updateItem fileURL]];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[updateItem fileURL]];
	[request setValue:[updater userAgentString] forHTTPHeaderField:@"User-Agent"];
	download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
}

- (void)download:(NSURLDownload *)d decideDestinationWithSuggestedFilename:(NSString *)name
{
    [sLogger log:@"Preparing to download file %@", name];
    
	// If name ends in .txt, the server probably has a stupid MIME configuration. We'll give the developer the benefit of the doubt and chop that off.
	if ([[name pathExtension] isEqualToString:@"txt"])
    {
		name = [name stringByDeletingPathExtension];
        [sLogger log:@"Removed .txt extension from file to download: is now %@", name];
    }
	
	NSString *downloadFileName = [NSString stringWithFormat:@"%@ %@", [host name], [updateItem versionString]];
    [sLogger log:@"Will download %@", downloadFileName];
    
    
	[tempDir release];
	tempDir = [[[host appSupportPath] stringByAppendingPathComponent:downloadFileName] retain];
	int cnt=1;
	while ([[NSFileManager defaultManager] fileExistsAtPath:tempDir] && cnt <= 999)
	{
		[tempDir release];
		tempDir = [[[host appSupportPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d", downloadFileName, cnt++]] retain];
	}
    [sLogger log:@"Will download to temporary directory '%@'", tempDir];
	
    // Create the temporary directory if necessary.
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
	BOOL success = YES;
    NSEnumerator *pathComponentEnumerator = [[tempDir pathComponents] objectEnumerator];
    NSString *pathComponentAccumulator = @"";
    NSString *currentPathComponent;
    while ((currentPathComponent = [pathComponentEnumerator nextObject])) {
        pathComponentAccumulator = [pathComponentAccumulator stringByAppendingPathComponent:currentPathComponent];
        if ([[NSFileManager defaultManager] fileExistsAtPath:pathComponentAccumulator]) continue;
        [sLogger log:@"Creating path component '%@'", pathComponentAccumulator];
        success &= [[NSFileManager defaultManager] createDirectoryAtPath:pathComponentAccumulator attributes:nil];
    }
#else
	BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:NULL];
#endif
	if (!success)
	{
		// Okay, something's really broken with this user's file structure.
        [sLogger log:@"ERROR: Failed to create temporary download directory. Download will be aborted."];
		[download cancel];
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.",tempDir] forKey:NSLocalizedDescriptionKey]]];
	}
	
	downloadPath = [[tempDir stringByAppendingPathComponent:name] retain];
    [sLogger log:@"File download target is %@", downloadPath];
	[download setDestination:downloadPath allowOverwrite:YES];
}

- (BOOL)validateUpdateDownloadedToPath:(NSString *)downloadedPath extractedToPath:(NSString *)extractedPath DSASignature:(NSString *)DSASignature publicDSAKey:(NSString *)publicDSAKey
{
    NSString *newBundlePath = [SUInstaller appPathInUpdateFolder:extractedPath forHost:host];
    if (newBundlePath)
    {
        NSError *error = nil;
        if ([SUCodeSigningVerifier codeSignatureIsValidAtPath:newBundlePath error:&error]) {
            [sLogger log:@"Code signature check in update passed"];
            return YES;
        } else {
            [sLogger log:@"Code signature check on update failed: %@", error];
        }
    }
    
    return [SUDSAVerifier validatePath:downloadedPath withEncodedDSASignature:DSASignature withPublicDSAKey:publicDSAKey];
}

- (void)downloadDidFinish:(NSURLDownload *)d
{
    [sLogger log:@"Download complete. Extracting update."];
	[self extractUpdate];
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
    [sLogger log:@"Update download failed with error: %@", error];
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil), NSLocalizedDescriptionKey, [error localizedDescription], NSLocalizedFailureReasonErrorKey, nil]]];
}

- (BOOL)download:(NSURLDownload *)download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
	// We don't want the download system to extract our gzips.
	// Note that we use a substring matching here instead of direct comparison because the docs say "application/gzip" but the system *uses* "application/x-gzip". This is a documentation bug.
	return ([encodingType rangeOfString:@"gzip"].location == NSNotFound);
}

- (void)extractUpdate
{
    [sLogger log:@"Extracting update from '%@'", downloadPath];
	SUUnarchiver *unarchiver = [SUUnarchiver unarchiverForPath:downloadPath updatingHost:host];
	if (!unarchiver)
	{
		[sLogger log:@"Sparkle Error: No valid unarchiver for %@!", downloadPath];
		[self unarchiverDidFail:nil];
		return;
	}
	CFRetain(unarchiver); // Manage this memory manually so we don't have to make it an IV.
	[unarchiver setDelegate:self];
	[unarchiver start];
}

- (void)failedToApplyDeltaUpdate
{
	// When a delta update fails to apply we fall back on updating via a full install.
    [sLogger log:@"ERROR: Failed to apply binary delta for update. Fall back to full install."];
	[updateItem release];
	updateItem = nonDeltaUpdateItem;
	nonDeltaUpdateItem = nil;

	[self downloadUpdate];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
    [sLogger log:@"Unarchiver finished extraction"];
	if (ua) { CFRelease(ua); }
	[self installWithToolAndRelaunch:YES];
}

- (void)unarchiverDidFail:(SUUnarchiver *)ua
{
    [sLogger log:@"ERROR: Failed to extract update from archive"];
	if (ua) { CFRelease(ua); }

	if ([updateItem isDeltaUpdate]) {
		[self failedToApplyDeltaUpdate];
		return;
	}

	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:[NSDictionary dictionaryWithObject:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil) forKey:NSLocalizedDescriptionKey]]];
}

- (BOOL)shouldInstallSynchronously { return NO; }

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
#if !ENDANGER_USERS_WITH_INSECURE_UPDATES
    [sLogger log:@"Performing code signing check for update"];
    if (![self validateUpdateDownloadedToPath:downloadPath extractedToPath:tempDir DSASignature:[updateItem DSASignature] publicDSAKey:[host publicDSAKey]])
    {
        [sLogger log:@"ERROR: Update code signature check failed - abort update"];
        
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUSignatureError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil), NSLocalizedDescriptionKey, @"The update is improperly signed.", NSLocalizedFailureReasonErrorKey, nil]]];
        return;
	}
    else
    {
        [sLogger log:@"Update passed code signature check"];
    }
#endif
    
    if (![updater mayUpdateAndRestart])
    {
        [sLogger log:@"WARNING: Update requires a restart, which was not permitted. Abort update"];
        [self abortUpdate];
        return;
    }
    
    // Give the host app an opportunity to postpone the install and relaunch.
    static BOOL postponedOnce = NO;
    if (!postponedOnce)
    {
        if ([[updater delegate] respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)])
        {
            [sLogger log:@"Will give host app an opportunity to postpone the update"];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:)]];
            [invocation setSelector:@selector(installWithToolAndRelaunch:)];
            [invocation setArgument:&relaunch atIndex:2];
            [invocation setTarget:self];
            postponedOnce = YES;
            if ([[updater delegate] updater:updater shouldPostponeRelaunchForUpdate:updateItem untilInvoking:invocation])
            {
                [sLogger log:@"Update was postponed by host app"];
                return;
            }
        }
    }
    else
    {
        // This method call was kicked by the host app after a postpone, so the host app is obviously ready for the update.
        // Don't ask them again, or we'll be trapped in a postponement loop.
        [sLogger log:@"Will not give host app an opportunity to postpone update: it's already been postponed before"];
    }

    
	if ([[updater delegate] respondsToSelector:@selector(updater:willInstallUpdate:)])
    {
        [sLogger log:@"Calling willInstallUpdate on updater delegate"];
		[[updater delegate] updater:updater willInstallUpdate:updateItem];
    }
	
	// Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
	NSString *relaunchPathToCopy = [SPARKLE_BUNDLE pathForResource:@"finish_installation" ofType:@"app"];
    NSString *targetPath = [[host appSupportPath] stringByAppendingPathComponent:[relaunchPathToCopy lastPathComponent]];
	// Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
	NSError *error = nil;
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
	[[NSFileManager defaultManager] createDirectoryAtPath: [targetPath stringByDeletingLastPathComponent] attributes: [NSDictionary dictionary]];
#else
	[[NSFileManager defaultManager] createDirectoryAtPath: [targetPath stringByDeletingLastPathComponent] withIntermediateDirectories: YES attributes: [NSDictionary dictionary] error: &error];
#endif

	// Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
	if( [SUPlainInstaller copyPathWithAuthentication: relaunchPathToCopy overPath: targetPath temporaryName: nil error: &error] )
    {
   		relaunchPath = [targetPath retain];
        [sLogger log:@"Relauncher copied to '%@'", relaunchPath];
    }
	else
    {
        [sLogger log:@"Failed to copy relauncher '%@' to temporary path '%@': %@", relaunchPathToCopy, relaunchPath, error];
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil), NSLocalizedDescriptionKey, [NSString stringWithFormat:@"Couldn't copy relauncher (%@) to temporary path (%@)! %@", relaunchPathToCopy, targetPath, (error ? [error localizedDescription] : @"")], NSLocalizedFailureReasonErrorKey, nil]]];
    }
	
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
    if ([[updater delegate] respondsToSelector:@selector(updaterWillRelaunchApplication:)])
    {
        [sLogger log:@"Notifying delegate that an application restart is imminent"];
        [[updater delegate] updaterWillRelaunchApplication:updater];
    }

    if(!relaunchPath || ![[NSFileManager defaultManager] fileExistsAtPath:relaunchPath])
    {
        [sLogger log:@"Relauncher isn't where we expected it to be (%@) - cannot restart app after upgrade", relaunchPath];
        // Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [host name]], NSLocalizedDescriptionKey, [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@)", relaunchPath], NSLocalizedFailureReasonErrorKey, nil]]];
        // We intentionally don't abandon the update here so that the host won't initiate another.
        return;
    }		
    
    NSString *pathToRelaunch = [host bundlePath];
    if ([[updater delegate] respondsToSelector:@selector(pathToRelaunchForUpdater:)])
    {
        NSString *newPath = [[updater delegate] pathToRelaunchForUpdater:updater];
        
        if (![pathToRelaunch isEqualToString: newPath])
        {
            [sLogger log:@"Updater delegate modified the relauncher path to '%@'", newPath];
        }
        
        pathToRelaunch = newPath;
    }
    
    NSString *relaunchToolPath = [relaunchPath stringByAppendingPathComponent: @"/Contents/MacOS/finish_installation"];
    [sLogger log:@"Full path to relaunch tool is '%@'", relaunchToolPath];
    
    [NSTask launchedTaskWithLaunchPath: relaunchToolPath arguments:[NSArray arrayWithObjects:[host bundlePath], pathToRelaunch, [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]], tempDir, relaunch ? @"1" : @"0", nil]];

    [sLogger log:@"App now terminating"];
    [NSApp terminate:self];
}

- (void)cleanUpDownload
{
    if (tempDir != nil)	// tempDir contains downloadPath, so we implicitly delete both here.
	{
		BOOL		success = NO;
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
        success = [[NSFileManager defaultManager] removeFileAtPath: tempDir handler: nil]; // Clean up the copied relauncher
#else
        NSError	*	error = nil;
        success = [[NSFileManager defaultManager] removeItemAtPath: tempDir error: &error]; // Clean up the copied relauncher
#endif
		if( !success )
			[[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[tempDir stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[tempDir lastPathComponent]] tag:NULL];
	}
    else
    {
        [sLogger log:@"WARNING: Temporary directory variable is nil - cannot clean up download"];
    }
}

- (void)installerForHost:(SUHost *)aHost failedWithError:(NSError *)error
{
	if (aHost != host)
    {
        [sLogger log:@"WARNING: installerForHost failedWithError called on us, but our host is not the host affected - this probably shouldn't happen"];
        return;
    }
    
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
    [[NSFileManager defaultManager] removeFileAtPath: relaunchPath handler: nil]; // Clean up the copied relauncher
#else
	NSError	*	dontThrow = nil;
	[[NSFileManager defaultManager] removeItemAtPath: relaunchPath error: &dontThrow]; // Clean up the copied relauncher
#endif
	[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while installing the update. Please try again later.", nil), NSLocalizedDescriptionKey, [error localizedDescription], NSLocalizedFailureReasonErrorKey, nil]]];
}

- (void)abortUpdate
{
    [sLogger log:@"Update aborted"];
	[[self retain] autorelease];	// In case the notification center was the last one holding on to us.
    [self cleanUpDownload];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super abortUpdate];
}

- (void)abortUpdateWithError:(NSError *)error
{
	if ([error code] != SUNoUpdateError) // Let's not bother logging this.
		[sLogger log:@"Sparkle Error: %@", [error localizedDescription]];
	if ([error localizedFailureReason])
		[sLogger log:@"Sparkle Error (continued): %@", [error localizedFailureReason]];
	if (download)
    {
        [sLogger log:@"The error occurred mid-download, so cancel the download"];
		[download cancel];
    }
	[self abortUpdate];
}

- (void)dealloc
{
	[updateItem release];
	[nonDeltaUpdateItem release];
	[download release];
	[downloadPath release];
	[tempDir release];
	[relaunchPath release];
	[super dealloc];
}

@end
