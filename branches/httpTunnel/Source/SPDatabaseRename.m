//
//  $Id: SPDatabaseRename.m 3745 2012-07-25 10:18:02Z stuart02 $
//
//  SPDatabaseRename.m
//  sequel-pro
//
//  Created by David Rekowski on April 13, 2010.
//  Copyright (c) 2010 David Rekowski. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <http://code.google.com/p/sequel-pro/>

#import "SPDatabaseRename.h"
#import "SPTableCopy.h"
#import "SPViewCopy.h"
#import "SPTablesList.h"

#import <SPMySQL/SPMySQL.h>

@interface SPDatabaseRename ()

- (BOOL)_createDatabase:(NSString *)database;
- (BOOL)_dropDatabase:(NSString *)database;

- (void)_moveTables:(NSArray *)tables fromDatabase:(NSString *)sourceDatabase toDatabase:(NSString *)targetDatabase;
- (void)_moveViews:(NSArray *)views fromDatabase:(NSString *)sourceDatabase toDatabase:(NSString *)targetDatabase;

@end

@implementation SPDatabaseRename

- (BOOL)renameDatabaseFrom:(NSString *)sourceDatabase to:(NSString *)targetDatabase
{
	NSArray *tables = nil;
	NSArray *views = nil;
	
	// Check, whether the source database exists and the target database doesn't
	BOOL sourceExists = [[connection databases] containsObject:sourceDatabase];
	BOOL targetExists = [[connection databases] containsObject:targetDatabase];
	
	if (sourceExists && !targetExists) {
		tables = [tablesList allTableNames];
		views = [tablesList allViewNames];
	}
	else {
		return NO;
	}
		
	BOOL success = [self _createDatabase:targetDatabase];
	
	[self _moveTables:tables fromDatabase:sourceDatabase toDatabase:targetDatabase];
	
	tables = [connection tablesFromDatabase:sourceDatabase];
		
	if ([tables count] == 0) {
		[self _dropDatabase:sourceDatabase];
	} 
		
	return success;
}

#pragma mark -
#pragma mark Private API

/**
 * This method creates a new database.
 *
 * @param NSString newDatabaseName name of the new database to be created
 * @return BOOL YES on success, otherwise NO
 */
- (BOOL)_createDatabase:(NSString *)database 
{	
	[connection queryString:[NSString stringWithFormat:@"CREATE DATABASE %@", [database backtickQuotedString]]];	
	
	return ![connection queryErrored];
}

/**
 * This method drops a database.
 *
 * @param NSString databaseName name of the database to drop
 * @return BOOL YES on success, otherwise NO
 */
- (BOOL)_dropDatabase:(NSString *)database 
{	
	[connection queryString:[NSString stringWithFormat:@"DROP DATABASE %@", [database backtickQuotedString]]];	
	
	return ![connection queryErrored];
}

- (void)_moveTables:(NSArray *)tables fromDatabase:(NSString *)sourceDatabase toDatabase:(NSString *)targetDatabase
{
	SPTableCopy *dbActionTableCopy = [[SPTableCopy alloc] init];
	
	[dbActionTableCopy setConnection:connection];
	
	for (NSString *table in tables) 
	{
		[dbActionTableCopy moveTable:table from:sourceDatabase to:targetDatabase];
	}
	
	[dbActionTableCopy release];
}

- (void)_moveViews:(NSArray *)views fromDatabase:(NSString *)sourceDatabase toDatabase:(NSString *)targetDatabase
{
	SPViewCopy *dbActionViewCopy = [[SPViewCopy alloc] init];
	
	[dbActionViewCopy setConnection:connection];
	
	for (NSString *view in views) 
	{
		[dbActionViewCopy moveView:view from:sourceDatabase to:targetDatabase];
	}
	
	[dbActionViewCopy release];
}

@end