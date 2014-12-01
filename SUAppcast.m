//
//  SUAppcast.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "SUAppcast.h"
#import "SUConstants.h"
#import "SULog.h"

@interface NSXMLElement (SUAppcastExtensions)
- (NSDictionary *)attributesAsDictionary;
@end

@implementation NSXMLElement (SUAppcastExtensions)
- (NSDictionary *)attributesAsDictionary
{
	NSEnumerator *attributeEnum = [[self attributes] objectEnumerator];
	NSXMLNode *attribute;
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

	while ((attribute = [attributeEnum nextObject]))
		[dictionary setObject:[attribute stringValue] forKey:[attribute name]];
	return dictionary;
}
@end

@interface SUAppcast () <NSURLDownloadDelegate>
- (void)reportError:(NSError *)error;
- (NSXMLNode *)bestNodeInNodes:(NSArray *)nodes;
@end

@implementation SUAppcast

static Logger *sLogger;

+(void) initialize {
    sLogger = [[Logger alloc] initWithClass:self];
}

- (void)dealloc
{
	[items release];
	items = nil;
	[userAgentString release];
	userAgentString = nil;
	[downloadFilename release];
	downloadFilename = nil;
	[download release];
	download = nil;
	
	[super dealloc];
}

- (NSArray *)items
{
	return items;
}

- (void)fetchAppcastFromURL:(NSURL *)url
{
    [sLogger log:@"Fetch appcast from URL %@", url];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
    
    if (userAgentString)
    {
        [sLogger log:@"Use User-Agent '%@'", userAgentString];
        [request setValue:userAgentString forHTTPHeaderField:@"User-Agent"];
    }
    
    download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
}

- (void)download:(NSURLDownload *)aDownload decideDestinationWithSuggestedFilename:(NSString *)filename
{
	NSString* destinationFilename = NSTemporaryDirectory();
	if (destinationFilename)
	{
		destinationFilename = [destinationFilename stringByAppendingPathComponent:filename];
        [sLogger log:@"Download location for appcast will be: '%@'", destinationFilename];
		[download setDestination:destinationFilename allowOverwrite:NO];
	}
    else
    {
        [sLogger log:@"ERROR: Failed to obtain temporary directory for appcast download"];
    }
}

- (void)download:(NSURLDownload *)aDownload didCreateDestination:(NSString *)path
{
    [downloadFilename release];
    downloadFilename = [path copy];
    [sLogger log:@"Download location for appcast will be: '%@'", downloadFilename];
}

- (void)downloadDidFinish:(NSURLDownload *)aDownload
{
    [sLogger log:@"Appcast download complete"];
	NSError *error = nil;
	
	NSXMLDocument *document = nil;
	BOOL failed = NO;
	NSArray *xmlItems = nil;
	NSMutableArray *appcastItems = [NSMutableArray array];
	
	if (downloadFilename)
	{
        NSUInteger options = 0;
        if (NSAppKitVersionNumber < NSAppKitVersionNumber10_7) {
            // In order to avoid including external entities when parsing the appcast (a potential security vulnerability; see https://github.com/andymatuschak/Sparkle/issues/169), we ask NSXMLDocument to "tidy" the XML first. This happens to remove these external entities; it wouldn't be a future-proof approach, but it worked in these historical versions of OS X, and we have a more rigorous approach for 10.7+.
            options = NSXMLDocumentTidyXML;
            [sLogger log:@"Asking NSXMLDocument to tidy the appcast XML"];
        } else {
            // In 10.7 and later, there's a real option for the behavior we desire.
            [sLogger log:@"Enforce policy NSXMLNodeLoadExternalEntitiesSameOriginOnly"];
            options = NSXMLNodeLoadExternalEntitiesSameOriginOnly;
        }
		document = [[[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:downloadFilename] options:options error:&error] autorelease];
	
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
		[[NSFileManager defaultManager] removeFileAtPath:downloadFilename handler:nil];
#else
		[[NSFileManager defaultManager] removeItemAtPath:downloadFilename error:nil];
#endif
		[downloadFilename release];
		downloadFilename = nil;
	}
	else
	{
        [sLogger log:@"ERROR: Appcast download failed"];
		failed = YES;
	}
    
    if (nil == document)
    {
        [sLogger log:@"ERROR: Appcast parsing failed; XML document is nil. Error: %@", error];
        failed = YES;
    }
    else
    {
        xmlItems = [document nodesForXPath:@"/rss/channel/item" error:&error];
        if (nil == xmlItems)
        {
            [sLogger log:@"ERROR: Appcast parsing failed; xmlItems=nil. Error: %@", error];
            failed = YES;
        }
    }
    
	if (failed == NO)
    {
        [sLogger log:@"Syntax-level parse of XML was successful. Will now import appcast data from XML tree."];
		NSEnumerator *nodeEnum = [xmlItems objectEnumerator];
		NSXMLNode *node;
		NSMutableDictionary *nodesDict = [NSMutableDictionary dictionary];
		NSMutableDictionary *dict = [NSMutableDictionary dictionary];
		
		while (failed == NO && (node = [nodeEnum nextObject]))
        {
			// First, we'll "index" all the first-level children of this appcast item so we can pick them out by language later.
            if ([[node children] count])
            {
                node = [node childAtIndex:0];
                while (nil != node)
                {
                    NSString *name = [node name];
                    if (name)
                    {
                        NSMutableArray *nodes = [nodesDict objectForKey:name];
                        if (nodes == nil)
                        {
                            nodes = [NSMutableArray array];
                            [nodesDict setObject:nodes forKey:name];
                        }
                        [nodes addObject:node];
                    }
                    node = [node nextSibling];
                }
            }
            
            NSEnumerator *nameEnum = [nodesDict keyEnumerator];
            NSString *name;
            while ((name = [nameEnum nextObject]))
            {
                node = [self bestNodeInNodes:[nodesDict objectForKey:name]];
				if ([name isEqualToString:@"enclosure"])
				{
					// enclosure is flattened as a separate dictionary for some reason
					NSDictionary *encDict = [(NSXMLElement *)node attributesAsDictionary];
					[dict setObject:encDict forKey:@"enclosure"];
					
				}
                else if ([name isEqualToString:@"pubDate"])
                {
					// pubDate is expected to be an NSDate by SUAppcastItem, but the RSS class was returning an NSString
					NSDate *date = [NSDate dateWithNaturalLanguageString:[node stringValue]];
					if (date)
						[dict setObject:date forKey:name];
				}
				else if ([name isEqualToString:@"sparkle:deltas"])
				{
					NSMutableArray *deltas = [NSMutableArray array];
					NSEnumerator *childEnum = [[node children] objectEnumerator];
					NSXMLNode *child;
					while ((child = [childEnum nextObject])) {
						if ([[child name] isEqualToString:@"enclosure"])
							[deltas addObject:[(NSXMLElement *)child attributesAsDictionary]];
					}
					[dict setObject:deltas forKey:@"deltas"];
				}
				else if (name != nil)
				{
					// add all other values as strings
					[dict setObject:[[node stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey:name];
				}
            }
            
			NSString *errString;
			SUAppcastItem *anItem = [[[SUAppcastItem alloc] initWithDictionary:dict failureReason:&errString] autorelease];
            if (anItem)
            {
                [appcastItems addObject:anItem];
			}
            else
            {
				[sLogger log:@"ERROR: Failed to parse appcast item: %@.\nAppcast dictionary was: %@", errString, dict];
            }
            [nodesDict removeAllObjects];
            [dict removeAllObjects];
		}
	}
	
	if ([appcastItems count])
    {
		NSSortDescriptor *sort = [[[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO] autorelease];
		[appcastItems sortUsingDescriptors:[NSArray arrayWithObject:sort]];
		items = [appcastItems copy];
	}
	
	if (failed)
    {
        [sLogger log:@"Parsing of appcast XML failed. Update will be aborted"];
        [self reportError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred while parsing the update feed.", nil), NSLocalizedDescriptionKey, nil]]];
	}
    else
    {
        if ([delegate respondsToSelector:@selector(appcastDidFinishLoading:)])
        {
            [sLogger log:@"Notifying delegate that the appcast feed loaded successfully"];
            [delegate appcastDidFinishLoading:self];
        }
        
        [sLogger log:@"THe appcast feed was loaded successfully"];
	}
}

- (void)download:(NSURLDownload *)aDownload didFailWithError:(NSError *)error
{
    [sLogger log:@"ERROR: Appcast download failed with error: %@", error];
	if (downloadFilename)
	{
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
		[[NSFileManager defaultManager] removeFileAtPath:downloadFilename handler:nil];
#else
		[[NSFileManager defaultManager] removeItemAtPath:downloadFilename error:nil];
#endif
	}
    [downloadFilename release];
    downloadFilename = nil;
    
	[self reportError:error];
}

- (NSURLRequest *)download:(NSURLDownload *)aDownload willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
    [sLogger log:@"Downloader will send redirect response: %@", [redirectResponse URL]];
	return request;
}

- (void)reportError:(NSError *)error
{
	if ([delegate respondsToSelector:@selector(appcast:failedToLoadWithError:)])
	{
		[delegate appcast:self failedToLoadWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastError userInfo:[NSDictionary dictionaryWithObjectsAndKeys:SULocalizedString(@"An error occurred in retrieving update information. Please try again later.", nil), NSLocalizedDescriptionKey, [error localizedDescription], NSLocalizedFailureReasonErrorKey, nil]]];
	}
}

- (NSXMLNode *)bestNodeInNodes:(NSArray *)nodes
{
	// We use this method to pick out the localized version of a node when one's available.
    if ([nodes count] == 1)
        return [nodes objectAtIndex:0];
    else if ([nodes count] == 0)
        return nil;
    
    NSEnumerator *nodeEnum = [nodes objectEnumerator];
    NSXMLElement *node;
    NSMutableArray *languages = [NSMutableArray array];
    NSString *lang;
    NSUInteger i;
    while ((node = [nodeEnum nextObject]))
    {
        lang = [[node attributeForName:@"xml:lang"] stringValue];
        [languages addObject:(lang ? lang : @"")];
    }
    lang = [[NSBundle preferredLocalizationsFromArray:languages] objectAtIndex:0];
    i = [languages indexOfObject:([languages containsObject:lang] ? lang : @"")];
    if (i == NSNotFound)
        i = 0;
    return [nodes objectAtIndex:i];
}

- (void)setUserAgentString:(NSString *)uas
{
	if (uas != userAgentString)
	{
        [sLogger log:@"Set User-Agent string to %@", uas];
		[userAgentString release];
		userAgentString = [uas copy];
	}
}

- (void)setDelegate:del
{
	delegate = del;
}

@end
