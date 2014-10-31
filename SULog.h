/*
 *  SULog.h
 *  EyeTV
 *
 *  Created by Uli Kusterer on 12/03/2009.
 *  Copyright 2008 Elgato Systems GmbH. All rights reserved.
 *
 */

/*
	Log output for troubleshooting Sparkle failures on end-user machines.
	Your tech support will hug you if you tell them about this.
*/

#pragma once

// -----------------------------------------------------------------------------
//	Headers:
// -----------------------------------------------------------------------------

#include <Foundation/Foundation.h>

@interface Logger : NSObject
+(void) setLogFile: (NSString *)logFile;
+(void) wrapLogsIfNecessary;
-(id) initWithClass: (Class) clazz;
-(void) log: (NSString *)format, ...;
@end


