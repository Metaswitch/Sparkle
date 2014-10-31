/*
 *  SULog.m
 *  EyeTV
 *
 *  Created by Uli Kusterer on 12/03/2009.
 *  Copyright 2009 Elgato Systems GmbH. All rights reserved.
 *
 */

// -----------------------------------------------------------------------------
//	Headers:
// -----------------------------------------------------------------------------

#include "SULog.h"


// -----------------------------------------------------------------------------
//	Constants:
// -----------------------------------------------------------------------------

#define LOG_FILE_MAX_BYTES  5000000LL
#define NUM_LOG_FILES       3

static NSString *sLogFile;
static NSDateFormatter *dateFormatter;

@implementation Logger

NSString *className;


+(void) initialize {
    dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    
    // @@SMK: Remove this.
    [self setLogFile: @"~/Library/Logs/SparkleFooLog.log"];
}

+(void) setLogFile: (NSString *) logFile {
    @synchronized(self) {
        if (sLogFile) {
            [sLogFile release];
        }
        
        sLogFile = [logFile stringByExpandingTildeInPath];
        [sLogFile retain];
        NSLog(@"Set log file: %@", sLogFile);
    }
}

+(void) wrapLogsIfNecessary {
    @synchronized(self) {
        unsigned long long fileSize = [[[NSFileManager defaultManager]
                                        attributesOfItemAtPath:sLogFile error:nil] fileSize];
        if (fileSize > LOG_FILE_MAX_BYTES) {
            // Rename each .log.n file to .log.(n+1).
            // Rename the original .log file to .log.1.
            // If there are now too many log files, delete the oldest.
            for (int ii = NUM_LOG_FILES - 1; ii >= 0; ii--) {
                
                // Determine the path of the file to be renamed/deleted.
                NSString *originalFile;
                if (ii == 0) {
                    originalFile = sLogFile;
                }
                else {
                    originalFile = [NSString stringWithFormat: @"%@.%d", sLogFile, ii];
                }
                
                // Perform the rename/delete operation.
                if ([[NSFileManager defaultManager] fileExistsAtPath: originalFile]) {
                    if (ii == NUM_LOG_FILES - 1) {
                        // We already have the maximum number of log files, so the oldest needs
                        // to be deleted rather than moved.
                        [[NSFileManager defaultManager] removeItemAtPath: originalFile error:nil];
                    }
                    else {
                        NSString *toPath = [NSString stringWithFormat: @"%@.%d", sLogFile, ii + 1];
                        bool success = [[NSFileManager defaultManager]
                                        moveItemAtPath:originalFile  toPath:toPath error:nil];
                        if (!success) {
                            // We failed to rename the log file; just delete it so that hopefully the newer
                            // logs will survive. If this fails, there's nothing else we can do.
                            [[NSFileManager defaultManager] removeItemAtPath: originalFile error:nil];
                        }
                    }
                }
            }
        }
    }
}

- (id) initWithClass: (Class) clazz {
    if (self = [super init]) {
        className = NSStringFromClass(clazz);
        [className retain];
    }
    
    return self;
}

-(void) log: (NSString *) format, ... {
    @synchronized([self class]) {
        [[self class] wrapLogsIfNecessary];
        
        va_list ap;
        va_start(ap, format);
        NSString*	theStr = [[[NSString alloc] initWithFormat: format arguments: ap] autorelease];
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath: sLogFile];
    
        if (file == nil) {
            [[NSFileManager defaultManager] createFileAtPath:sLogFile contents:nil attributes:nil];
            file = [NSFileHandle fileHandleForWritingAtPath: sLogFile];
        }
        else {
            [file seekToEndOfFile];
        }

        theStr = [NSString stringWithFormat: @"%@: %@: %@\n",
                  [dateFormatter stringFromDate: [NSDate date]],
                  className, theStr];
        NSData*	theData = [theStr dataUsingEncoding: NSUTF8StringEncoding];

        [file writeData: theData];
        [file closeFile];

        
        va_end(ap);
    }
}

@end
