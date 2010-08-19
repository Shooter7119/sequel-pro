//
//  $Id$
//
//  SPLogger.m
//  sequel-pro
//
//  Created by Rowan Beentje on 17/06/2009.
//  Copyright 2009 Rowan Beentje. All rights reserved.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//  More info at <http://code.google.com/p/sequel-pro/>

#import "SPLogger.h"

static SPLogger *logger = nil;

/**
 * This is a small class intended to aid in user issue debugging; by including
 * the header file, and using [[SPLogger logger] log:@"String with format", ...]
 * a file will be created on the user's desktop including timestamps and
 * the log message.
 * This allows use of fine-grained and detailed logging, without asking the user
 * to copy text from a console log via NSLog.
 * As each log line must by synched to disk as soon as it is received, for safety,
 * this class can add a performance hit when lots of logging is used.
 */

@implementation SPLogger

/*
 * Returns the shared logger object.
 */
+ (SPLogger *)logger
{
	@synchronized(self) {
		if (logger == nil) {
			[[self alloc] init];
		}
	}
	
	return logger;
}

#pragma mark -
#pragma mark Initialisation and teardown

+ (id)allocWithZone:(NSZone *)zone
{    
    @synchronized(self) {
        if (logger == nil) {
            logger = [super allocWithZone:zone];
            
            return logger;
        }
    }
    
    return nil;
}

- (id)init
{
	if ((self = [super init])) {
		NSArray *paths = NSSearchPathForDirectoriesInDomains (NSDesktopDirectory, NSUserDomainMask, YES);
		NSString *logFilePath = [NSString stringWithFormat:@"%@/Sequel Pro Debug Log.txt", [paths objectAtIndex:0]];

		initializedSuccessfully = YES;
		
		// Check if the debug file exists, and is writable
		if ( [[NSFileManager defaultManager] fileExistsAtPath:logFilePath] ) {
			if ( ![[NSFileManager defaultManager] isWritableFileAtPath:logFilePath] ) {
				initializedSuccessfully = NO;
				NSRunAlertPanel(@"Logging error", @"Log file exists but is not writeable; no debug log will be generated!", @"OK", nil, nil);
			}
		
		// Otherwise try creating one
		} else {
			if ( ![[NSFileManager defaultManager] createFileAtPath:logFilePath contents:[NSData data] attributes:nil] ) {
				initializedSuccessfully = NO;
				NSRunAlertPanel(@"Logging error", @"Could not create log file for writing; no debug log will be generated!", @"OK", nil, nil);
			}
		}
		
		// Get a file handle to the file if possible
		if (initializedSuccessfully) {
			logFileHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
			if (!logFileHandle) {
				initializedSuccessfully = NO;
				NSRunAlertPanel(@"Logging error", @"Could not open log file for writing; no debug log will be generated!", @"OK", nil, nil);
			} else {
				[logFileHandle retain];
				[logFileHandle seekToEndOfFile];
				NSString *bundleName = [[NSFileManager defaultManager] displayNameAtPath:[[NSBundle mainBundle] bundlePath]];
				NSMutableString *logStart = [NSMutableString stringWithString:@"\n\n\n==========================================================================\n\n"];
				[logStart appendString:[NSString stringWithFormat:@"%@ (r%i)\n", bundleName, [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] intValue]]];
				[logFileHandle writeData:[logStart dataUsingEncoding:NSUTF8StringEncoding]];
			}
		}
	}
	
	return self;
}

#pragma mark -
#pragma mark Logging functions

- (void) log:(NSString *)theString, ...
{
	if (!initializedSuccessfully) return;

	// Extract any supplied arguments and build the formatted log string
	va_list arguments;
	va_start(arguments, theString);
	NSString *logString = [[NSString alloc] initWithFormat:theString arguments:arguments];
	va_end(arguments);

	// Write the log line, forcing an immediate write to disk to ensure logging
	[logFileHandle writeData:[[NSString stringWithFormat:@"%@  %@\n", [[NSDate date] descriptionWithCalendarFormat:@"%H:%M:%S" timeZone:nil locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]], logString] dataUsingEncoding:NSUTF8StringEncoding]];
	[logFileHandle synchronizeFile];

	[logString release];
}

- (void) outputTimeString
{
	if (!initializedSuccessfully) return;

	[logFileHandle writeData:[[NSString stringWithFormat:@"Launched at %@\n\n", [[NSDate date] description]] dataUsingEncoding:NSUTF8StringEncoding]];
}

@end