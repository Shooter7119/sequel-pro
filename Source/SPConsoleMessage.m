//
//  SPConsoleMessage.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on Mar 12, 2009
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

#import "SPConsoleMessage.h"

@implementation SPConsoleMessage

+ (SPConsoleMessage *)consoleMessageWithMessage:(NSString *)message date:(NSDate *)date
{
	return [[[SPConsoleMessage alloc] initWithMessage:message date:date] autorelease];
}

- (id)initWithMessage:(NSString *)consoleMessage date:(NSDate *)date
{
	if ((self = [super init])) {
		isError = NO;
		messageDate = [date copy];
		message = [[NSString alloc] initWithString:consoleMessage];
	}
	
	return self;
}


- (BOOL)isError
{
	return isError;
}

- (NSDate *)messageDate
{
	return messageDate;
}

- (NSString *)message
{
	return message;
}

- (void)setIsError:(BOOL)error
{
	isError = error;
}

- (void)setMessageDate:(NSDate *)theDate
{
	if (messageDate) [messageDate release];
	messageDate = [theDate copy];
}

- (void)setMessage:(NSString *)theMessage
{
	if (message) [message release];
	message = [[NSString alloc] initWithString:theMessage];
}

- (void)dealloc
{
	[message release], message = nil;
	[messageDate release], messageDate = nil;
	
	[super dealloc];
}

@end
