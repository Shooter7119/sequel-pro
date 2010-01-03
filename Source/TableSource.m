//
//  $Id$
//
//  TableSource.m
//  sequel-pro
//
//  Created by lorenz textor (lorenz@textor.ch) on Wed May 01 2002.
//  Copyright (c) 2002-2003 Lorenz Textor. All rights reserved.
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

#import "TableSource.h"
#import "TableDocument.h"
#import "TablesList.h"
#import "SPTableData.h"
#import "SPSQLParser.h"
#import "SPStringAdditions.h"
#import "SPArrayAdditions.h"
#import "SPConstants.h"

@interface TableSource (PrivateAPI)

- (void)_addIndex;
- (void)_removeFieldAndForeignKey:(BOOL)removeForeignKey;
- (void)_removeIndexAndForeignKey:(BOOL)removeForeignKey;

@end

@implementation TableSource

/*
loads aTable, put it in an array, update the tableViewColumns and reload the tableView
*/
- (void)loadTable:(NSString *)aTable
{
	NSEnumerator *enumerator;
	id field;
	NSArray *extrasArray;
	NSMutableDictionary *tempDefaultValues;
	NSEnumerator *extrasEnumerator;
	id extra;
	int i;
	SPSQLParser *fieldParser;
	BOOL enableInteraction = ![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableStructure] || ![tableDocumentInstance isWorking];

	// Check whether a save of the current row is required.
	if ( ![self saveRowOnDeselect] ) return;

	if (selectedTable) [selectedTable release];
	if (aTable == nil) {
		selectedTable = nil;
	} else {
		selectedTable = [[NSString alloc] initWithString:aTable];
	}
	[tableSourceView deselectAll:self];
	[indexView deselectAll:self];

	if ( isEditingRow )
		return;

	// empty variables
	[enumFields removeAllObjects];

	if ( [aTable isEqualToString:@""] || !aTable ) {
		[tableFields removeAllObjects];
		[indexes removeAllObjects];
		[tableSourceView reloadData];
		[indexView reloadData];
		[addFieldButton setEnabled:NO];
		[copyFieldButton setEnabled:NO];
		[removeFieldButton setEnabled:NO];
		[addIndexButton setEnabled:NO];
		[removeIndexButton setEnabled:NO];
		[editTableButton setEnabled:NO];

		return;
	}
	
	// Enable edit table button
	[editTableButton setEnabled:enableInteraction];

	//query started
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:tableDocumentInstance];
  
	//perform queries and load results in array (each row as a dictionary)
	tableSourceResult = [[mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM %@", [selectedTable backtickQuotedString]]] retain];
	[tableSourceResult setReturnDataAsStrings:YES];
	
	// listFieldsFromTable is broken in the current version of the framework (no back-ticks for table name)!
	//	tableSourceResult = [[mySQLConnection listFieldsFromTable:selectedTable] retain];
	//	[tableFields setArray:[[self fetchResultAsArray:tableSourceResult] retain]];
	[tableFields setArray:[self fetchResultAsArray:tableSourceResult]];
	[tableSourceResult release];

	indexResult = [[mySQLConnection queryString:[NSString stringWithFormat:@"SHOW INDEX FROM %@", [selectedTable backtickQuotedString]]] retain];
	[indexResult setReturnDataAsStrings:YES];
	//	[indexes setArray:[[self fetchResultAsArray:indexResult] retain]];
	[indexes setArray:[self fetchResultAsArray:indexResult]];
	[indexResult release];
	
	//get table default values
	if ( defaultValues ) {
		[defaultValues release];
		defaultValues = nil;
	}
	
	tempDefaultValues = [NSMutableDictionary dictionary];
	for ( i = 0 ; i < [tableFields count] ; i++ ) {
		[tempDefaultValues setObject:[[tableFields objectAtIndex:i] objectForKey:@"Default"] forKey:[[tableFields objectAtIndex:i] objectForKey:@"Field"]];
	}
	defaultValues = [[NSDictionary dictionaryWithDictionary:tempDefaultValues] retain];
	
	//put field length and extras in separate key
	enumerator = [tableFields objectEnumerator];

	while ( (field = [enumerator nextObject]) ) {
		NSString *type;
		NSString *length;
		NSString *extras;

		// Set up the field parser with the type definition
		fieldParser = [[SPSQLParser alloc] initWithString:[field objectForKey:@"Type"]];

		// Pull out the field type; if no brackets are found, this returns nil - in which case simple values can be used.
		type = [fieldParser trimAndReturnStringToCharacter:'(' trimmingInclusively:YES returningInclusively:NO];
		if (!type) {
			type = [NSString stringWithString:fieldParser];
			length = @"";
			extras = @"";
		} else {

			// Pull out the length, which may include enum/set values
			length = [fieldParser trimAndReturnStringToCharacter:')' trimmingInclusively:YES returningInclusively:NO];
			if (!length) length = @"";

			// Separate any remaining extras
			extras = [NSString stringWithString:fieldParser];
			if (!extras) extras = @"";
		}

		[fieldParser release];

		// Get possible values if the field is an enum or a set
		if ([type isEqualToString:@"enum"] || [type isEqualToString:@"set"]) {
			SPSQLParser *valueParser = [[SPSQLParser alloc] initWithString:length];
			NSMutableArray *possibleValues = [[NSMutableArray alloc] initWithArray:[valueParser splitStringByCharacter:',']];
			for (i = 0; i < [possibleValues count]; i++) {
				[valueParser setString:[possibleValues objectAtIndex:i]];
				[possibleValues replaceObjectAtIndex:i withObject:[valueParser unquotedString]];
			}
			[enumFields setObject:[NSArray arrayWithArray:possibleValues] forKey:[field objectForKey:@"Field"]];
			[possibleValues release];
			[valueParser release];
		}
		
		// For timestamps check to see whether "on update CURRENT_TIMESTAMP" - not returned
		// by SHOW COLUMNS - should be set from the table data store
		if ([type isEqualToString:@"timestamp"]
			&& [[[tableDataInstance columnWithName:[field objectForKey:@"Field"]] objectForKey:@"onupdatetimestamp"] intValue])
		{
			[field setObject:@"on update CURRENT_TIMESTAMP" forKey:@"Extra"];
		}

		// scan extras for values like unsigned, zerofill, binary
		extrasArray = [extras componentsSeparatedByString:@" "];
		extrasEnumerator = [extrasArray objectEnumerator];
		
		while ( (extra = [extrasEnumerator nextObject]) ) {
			if ( [extra isEqualToString:@"unsigned"] ) {
				[field setObject:@"1" forKey:@"unsigned"];
			} else if ( [extra isEqualToString:@"zerofill"] ) {
				[field setObject:@"1" forKey:@"zerofill"];
			} else if ( [extra isEqualToString:@"binary"] ) {
				[field setObject:@"1" forKey:@"binary"];
			} else {
				if ( ![extra isEqualToString:@""] )
					NSLog(@"ERROR: unknown option in field definition: %@", extra);
			}
		}
		
		[field setObject:type forKey:@"Type"];
		[field setObject:length forKey:@"Length"];
	}
	
	// If a view is selected, disable the buttons; otherwise enable.
	BOOL editingEnabled = ([tablesListInstance tableType] == SP_TABLETYPE_TABLE) && enableInteraction;
	[addFieldButton setEnabled:editingEnabled];
	[addIndexButton setEnabled:editingEnabled];
    
    //the following three buttons will only be enabled if a row field/index is selected!
	[copyFieldButton setEnabled:NO];
	[removeFieldButton setEnabled:NO];
	[removeIndexButton setEnabled:NO];
	
	//add columns to indexedColumnsField
	[indexedColumnsField removeAllItems];
	enumerator = [tableFields objectEnumerator];
	
	while ( (field = [enumerator nextObject]) ) {
		[indexedColumnsField addItemWithObjectValue:[field objectForKey:@"Field"]];
	}
	
	if ( [tableFields count] < 10 ) {
		[indexedColumnsField setNumberOfVisibleItems:[tableFields count]];
	} else {
		[indexedColumnsField setNumberOfVisibleItems:10];
	}
	
	[indexView reloadData];
	[tableSourceView reloadData];
	
	// display and *then* tile to force scroll bars to be in the correct position
	[[tableSourceView enclosingScrollView] display];
	[[tableSourceView enclosingScrollView] tile];
	
	// Enable 'Duplicate field' if at least one field is specified
	// if no field is selected 'Duplicate field' will copy the last field
	// Enable 'Duplicate field' only for tables!
	if ([tablesListInstance tableType] == SP_TABLETYPE_TABLE)
		[copyFieldButton setEnabled:enableInteraction && ([tableSourceView numberOfRows] > 0)];
	else
		[copyFieldButton setEnabled:NO];

	//query finished
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];
}

/**
 * Reloads the table (performing a new mysql-query)
 */
- (IBAction)reloadTable:(id)sender
{
	[tableDataInstance resetAllData];
	[tablesListInstance setStatusRequiresReload:YES];
	[self loadTable:selectedTable];
}

#pragma mark -
#pragma mark Edit methods

/**
 * Adds an empty row to the tableSource-array and goes into edit mode
 */
- (IBAction)addField:(id)sender
{
	// Check whether a save of the current row is required.
	if ( ![self saveRowOnDeselect] ) return;

	int insertIndex = ([tableSourceView numberOfSelectedRows] == 0 ? [tableSourceView numberOfRows] : [tableSourceView selectedRow] + 1);
	
	[tableFields insertObject:[NSMutableDictionary 
							   dictionaryWithObjects:[NSArray arrayWithObjects:@"", @"int", @"", @"0", @"0", @"0", ([prefs boolForKey:SPNewFieldsAllowNulls]) ? @"1" : @"0", @"", [prefs stringForKey:SPNullValue], @"None", nil]
							   forKeys:[NSArray arrayWithObjects:@"Field", @"Type", @"Length", @"unsigned", @"zerofill", @"binary", @"Null", @"Key", @"Default", @"Extra", nil]]
					  atIndex:insertIndex];

	[tableSourceView reloadData];
	[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:insertIndex] byExtendingSelection:NO];
	isEditingRow = YES;
	isEditingNewRow = YES;
	currentlyEditingRow = [tableSourceView selectedRow];
	[tableSourceView editColumn:0 row:insertIndex withEvent:nil select:YES];
}

/**
 * Copies a field and goes in edit mode for the new field
 */
- (IBAction)copyField:(id)sender
{
	NSMutableDictionary *tempRow;

	if ( ![tableSourceView numberOfSelectedRows] ) {
		[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:[tableSourceView numberOfRows]-1] byExtendingSelection:NO];
	}

	// Check whether a save of the current row is required.
	if ( ![self saveRowOnDeselect] ) return;
	
	//add copy of selected row and go in edit mode
	tempRow = [NSMutableDictionary dictionaryWithDictionary:[tableFields objectAtIndex:[tableSourceView selectedRow]]];
	[tempRow setObject:[[tempRow objectForKey:@"Field"] stringByAppendingString:@"Copy"] forKey:@"Field"];
	[tempRow setObject:@"" forKey:@"Key"];
	[tempRow setObject:@"None" forKey:@"Extra"];
	[tableFields addObject:tempRow];
	[tableSourceView reloadData];
	[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:[tableSourceView numberOfRows]-1] byExtendingSelection:NO];
	isEditingRow = YES;
	isEditingNewRow = YES;
	currentlyEditingRow = [tableSourceView selectedRow];
	[tableSourceView editColumn:0 row:[tableSourceView numberOfRows]-1 withEvent:nil select:YES];
}

/**
 * Ask the user to confirm that they really want to remove the selected field.
 */
- (IBAction)removeField:(id)sender
{
	if (![tableSourceView numberOfSelectedRows]) return;

	// Check whether a save of the current row is required.
	if (![self saveRowOnDeselect]) return;

	// Check if the user tries to delete the last defined field in table
	// Note that because of better menu item validation, this check will now never evaluate to true.
	if ([tableSourceView numberOfRows] < 2) {
		NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Error while deleting field", @"Error while deleting field")
										 defaultButton:NSLocalizedString(@"OK", @"OK button") 
									   alternateButton:nil 
										   otherButton:nil 
							 informativeTextWithFormat:NSLocalizedString(@"You cannot delete the last field in a table. Use 'Remove table' (DROP TABLE) instead.", @"You cannot delete the last field in that table. Use 'Remove table' (DROP TABLE) instead")];

		[alert setAlertStyle:NSCriticalAlertStyle];

		[alert beginSheetModalForWindow:tableWindow modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:@"cannotremovefield"];
		
	}
	
	NSString *field = [[tableFields objectAtIndex:[tableSourceView selectedRow]] objectForKey:@"Field"];
	
	BOOL hasForeignKey = NO;
	NSString *referencedTable = @"";
		
	// Check to see whether the user is attempting to remove a field that has foreign key constraints and thus
	// would result in an error if not dropped before removing the field.
	for (NSDictionary *constraint in [tableDataInstance getConstraints])
	{
		for (NSString *column in [constraint objectForKey:@"columns"])
		{
			if ([column isEqualToString:field]) {
				hasForeignKey = YES;
				referencedTable = [constraint objectForKey:@"ref_table"];
				break;
			}
		}
	}
	
	NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:NSLocalizedString(@"Delete field '%@'?", @"delete field message"), field]
									 defaultButton:NSLocalizedString(@"Delete", @"delete button")
								   alternateButton:NSLocalizedString(@"Cancel", @"cancel button") 
									   otherButton:nil 
						 informativeTextWithFormat:(hasForeignKey) ? [NSString stringWithFormat:NSLocalizedString(@"This field is part of a foreign key relationship with the table '%@'. This relationship must be removed before the field can be deleted.\n\nAre you sure you want to continue to remove the relationship and the field? This action cannot be undone.", @"delete field and foreign key informative message"), referencedTable] : [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the field '%@'? This action cannot be undone.", @"delete field informative message"), field]];
	
	[alert setAlertStyle:NSCriticalAlertStyle];
	
	NSArray *buttons = [alert buttons];
	
	// Change the alert's cancel button to have the key equivalent of return
	[[buttons objectAtIndex:0] setKeyEquivalent:@"d"];
	[[buttons objectAtIndex:0] setKeyEquivalentModifierMask:NSCommandKeyMask];
	[[buttons objectAtIndex:1] setKeyEquivalent:@"\r"];
	
	[alert beginSheetModalForWindow:tableWindow modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:(hasForeignKey) ? @"removeFieldAndForeignKey" : @"removeField"];
}

/**
 * Ask the user to confirm that they really want to remove the selected index.
 */
- (IBAction)removeIndex:(id)sender
{
	if (![indexView numberOfSelectedRows]) return;

	// Check whether a save of the current fields row is required.
	if (![self saveRowOnDeselect]) return;
	
	NSString *keyName    =  [[indexes objectAtIndex:[indexView selectedRow]] objectForKey:@"Key_name"];
	NSString *columnName =  [[indexes objectAtIndex:[indexView selectedRow]] objectForKey:@"Column_name"];
		
	BOOL hasForeignKey = NO;
	NSString *constraintName = @"";
	
	// Check to see whether the user is attempting to remove an index that a foreign key constraint depends on
	// thus would result in an error if not dropped before removing the index.
	for (NSDictionary *constraint in [tableDataInstance getConstraints])
	{
		for (NSString *column in [constraint objectForKey:@"columns"])
		{
			if ([column isEqualToString:columnName]) {
				hasForeignKey = YES;
				constraintName = [constraint objectForKey:@"name"];
				break;
			}
		}
	}
	
	NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:NSLocalizedString(@"Delete index '%@'?", @"delete index message"), keyName]
									 defaultButton:NSLocalizedString(@"Delete", @"delete button")
								   alternateButton:NSLocalizedString(@"Cancel", @"cancel button")
									   otherButton:nil 
						 informativeTextWithFormat:(hasForeignKey) ? [NSString stringWithFormat:NSLocalizedString(@"The foreign key relationship '%@' has a dependency on this index. This relationship must be removed before the index can be deleted.\n\nAre you sure you want to continue to remove the relationship and the index? This action cannot be undone.", @"delete index and foreign key informative message"), constraintName] : [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the index '%@'? This action cannot be undone.", @"delete index informative message"), keyName]];
	
	[alert setAlertStyle:NSCriticalAlertStyle];
	
	NSArray *buttons = [alert buttons];
	
	// Change the alert's cancel button to have the key equivalent of return
	[[buttons objectAtIndex:0] setKeyEquivalent:@"d"];
	[[buttons objectAtIndex:0] setKeyEquivalentModifierMask:NSCommandKeyMask];
	[[buttons objectAtIndex:1] setKeyEquivalent:@"\r"];
	
	[alert beginSheetModalForWindow:tableWindow modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:(hasForeignKey) ? @"removeIndexAndForeignKey" : @"removeIndex"];
}

#pragma mark -
#pragma mark Index sheet methods

/**
 * Opens the add new index sheet.
 */
- (IBAction)openIndexSheet:(id)sender
{
	int i;

	// Check whether a save of the current field row is required.
	if (![self saveRowOnDeselect]) return;

	// Set sheet defaults - key type PRIMARY, key name PRIMARY and disabled, and blank indexed columns
	[indexTypeField selectItemAtIndex:0];
	[indexNameField setEnabled:NO];
	[indexNameField setStringValue:@"PRIMARY"];
	[indexedColumnsField setStringValue:@""];
	[indexSheet makeFirstResponder:indexedColumnsField];
	
	// Check to see whether a primary key already exists for the table, and if so select an INDEX instead
	for (i = 0; i < [tableFields count]; i++) 
	{
		if ([[[tableFields objectAtIndex:i] objectForKey:@"Key"] isEqualToString:@"PRI"]) {
			[indexTypeField selectItemAtIndex:1];
			[indexNameField setEnabled:YES];
			[indexNameField setStringValue:@""];
			[indexSheet makeFirstResponder:indexNameField];
			break;
		}
	}

	// Begin the sheet
	[NSApp beginSheet:indexSheet
	   modalForWindow:tableWindow 
		modalDelegate:self
	   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) 
		  contextInfo:@"addIndex"];
}

/**
 * Closes the current sheet and stops the modal session
 */
- (IBAction)closeSheet:(id)sender
{
	[NSApp endSheet:[sender window] returnCode:[sender tag]];
	[[sender window] orderOut:self];
}

/*
invoked when user chooses an index type
*/
- (IBAction)chooseIndexType:(id)sender
{
	if ( [[indexTypeField titleOfSelectedItem] isEqualToString:@"PRIMARY KEY"] ) {
		[indexNameField setEnabled:NO];
		[indexNameField setStringValue:@"PRIMARY"];
	} else {
		[indexNameField setEnabled:YES];
		if ( [[indexNameField stringValue] isEqualToString:@"PRIMARY"] )
			[indexNameField setStringValue:@""];
	}
}

/*
reopens indexSheet after errorSheet (no columns specified)
*/
- (void)closeAlertSheet
{
	[self openIndexSheet:self];
}

/*
closes the keySheet
*/
- (IBAction)closeKeySheet:(id)sender
{
	[NSApp stopModalWithCode:[sender tag]];
}


#pragma mark -
#pragma mark Additional methods

/**
 * Sets the connection (received from TableDocument) and makes things that have to be done only once 
 */
- (void)setConnection:(MCPConnection *)theConnection
{
	mySQLConnection = theConnection;

	// Set up tableView
	[tableSourceView registerForDraggedTypes:[NSArray arrayWithObjects:@"SequelProPasteboard", nil]];
}

/*
fetches the result as an array with a dictionary for each row in it
*/
- (NSArray *)fetchResultAsArray:(MCPResult *)theResult
{
	unsigned long numOfRows = [theResult numOfRows];
	NSMutableArray *tempResult = [NSMutableArray arrayWithCapacity:numOfRows];
	NSMutableDictionary *tempRow;
	NSArray *keys;
	id key;
	int i;
	Class nullClass = [NSNull class];
	id prefsNullValue = [prefs objectForKey:SPNullValue];

	if (numOfRows) [theResult dataSeek:0];
	for ( i = 0 ; i < numOfRows ; i++ ) {
		tempRow = [NSMutableDictionary dictionaryWithDictionary:[theResult fetchRowAsDictionary]];

		//use NULL string from preferences instead of the NSNull oject returned by the framework
		keys = [tempRow allKeys];
		for (int i = 0; i < [keys count] ; i++) {
			key = NSArrayObjectAtIndex(keys, i);
			if ( [[tempRow objectForKey:key] isMemberOfClass:nullClass] )
				[tempRow setObject:prefsNullValue forKey:key];
		}
		// change some fields to be more human-readable or GUI compatible
		if ( [[tempRow objectForKey:@"Extra"] isEqualToString:@""] ) {
			[tempRow setObject:@"None" forKey:@"Extra"];
		}
		if ( [[tempRow objectForKey:@"Null"] isEqualToString:@"YES"] ) {
			[tempRow setObject:@"1" forKey:@"Null"];
		} else {
			[tempRow setObject:@"0" forKey:@"Null"];
		}
		[tempResult addObject:tempRow];
	}

	return tempResult;
}


/*
 * A method to be called whenever the selection changes or the table would be reloaded
 * or altered; checks whether the current row is being edited, and if so attempts to save
 * it.  Returns YES if no save was necessary or the save was successful, and NO if a save
 * was necessary but failed - also reselecting the row for re-editing.
 */
- (BOOL)saveRowOnDeselect
{
	// If no rows are currently being edited, or a save is already in progress, return success at once.
	if (!isEditingRow || isSavingRow) return YES;
	isSavingRow = YES;

	// Save any edits which have been made but not saved to the table yet.
	[tableWindow endEditingFor:nil];

	// Attempt to save the row, and return YES if the save succeeded.
	if ([self addRowToDB]) {
		isSavingRow = NO;
		return YES;
	}

	// Saving failed - reselect the old row and return failure.
	[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:currentlyEditingRow] byExtendingSelection:NO];
	isSavingRow = NO;
	return NO;
}

/**
 * tries to write row to mysql-db
 * returns YES if row written to db, otherwies NO
 * returns YES if no row is beeing edited and nothing has to be written to db
 */
- (BOOL)addRowToDB;
{
	int code;
	NSDictionary *theRow;
	NSMutableString *queryString;

	if (!isEditingRow || currentlyEditingRow == -1)
		return YES;
	
	if (alertSheetOpened)
		return NO;

	theRow = [tableFields objectAtIndex:currentlyEditingRow];
	
	if (isEditingNewRow) {
		// ADD syntax
		if ([[theRow objectForKey:@"Length"] isEqualToString:@""] || ![theRow objectForKey:@"Length"]) {
			
			queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ ADD %@ %@",
															[selectedTable backtickQuotedString], 
															[[theRow objectForKey:@"Field"] backtickQuotedString], 
															[theRow objectForKey:@"Type"]];
		} 
		else {
			queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ ADD %@ %@(%@)",
															[selectedTable backtickQuotedString], 
															[[theRow objectForKey:@"Field"] backtickQuotedString], 
															[theRow objectForKey:@"Type"],
															[theRow objectForKey:@"Length"]];
		}
	} 
	else {
		// CHANGE syntax
		if (([[theRow objectForKey:@"Length"] isEqualToString:@""]) || 
			(![theRow objectForKey:@"Length"]) || 
			([[theRow objectForKey:@"Type"] isEqualToString:@"datetime"])) 
		{
			// If the old row and new row dictionaries are equal then the user didn't actually change anything so don't continue 
			if ([oldRow isEqualToDictionary:theRow]) return YES;
			
			queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ CHANGE %@ %@ %@",
															[selectedTable backtickQuotedString], 
															[[oldRow objectForKey:@"Field"] backtickQuotedString], 
															[[theRow objectForKey:@"Field"] backtickQuotedString],
															[theRow objectForKey:@"Type"]];
		} 
		else {
			// If the old row and new row dictionaries are equal then the user didn't actually change anything so don't continue 
			if ([oldRow isEqualToDictionary:theRow]) return YES;
			
			queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ CHANGE %@ %@ %@(%@)",
															[selectedTable backtickQuotedString], 
															[[oldRow objectForKey:@"Field"] backtickQuotedString], 
															[[theRow objectForKey:@"Field"] backtickQuotedString],
															[theRow objectForKey:@"Type"], 
															[theRow objectForKey:@"Length"]];
		}
	}
	
	// Field specification
	if ([[theRow objectForKey:@"unsigned"] intValue] == 1) {
		[queryString appendString:@" UNSIGNED"];
	}
	
	if ( [[theRow objectForKey:@"zerofill"] intValue] == 1) {
		[queryString appendString:@" ZEROFILL"];
	}
	
	if ( [[theRow objectForKey:@"binary"] intValue] == 1) {
		[queryString appendString:@" BINARY"];
	}

	if ([[theRow objectForKey:@"Null"] intValue] == 0) {
		[queryString appendString:@" NOT NULL"];
	} else {
		[queryString appendString:@" NULL"];
	}
	
	// Don't provide any defaults for auto-increment fields
	if ([[theRow objectForKey:@"Extra"] isEqualToString:@"auto_increment"]) {
		[queryString appendString:@" "];
	} 
	else {
		// If a NULL value has been specified, and NULL is allowed, specify DEFAULT NULL
		if ([[theRow objectForKey:@"Default"] isEqualToString:[prefs objectForKey:SPNullValue]]) {
			if ([[theRow objectForKey:@"Null"] intValue] == 1) {
				[queryString appendString:@" DEFAULT NULL "];
			}
		} 
		// Otherwise, if CURRENT_TIMESTAMP was specified for timestamps, use that
		else if ([[theRow objectForKey:@"Type"] isEqualToString:@"timestamp"] && 
				 [[[theRow objectForKey:@"Default"] uppercaseString] isEqualToString:@"CURRENT_TIMESTAMP"])
		{
			[queryString appendString:@" DEFAULT CURRENT_TIMESTAMP "];

		}
		// If the field is of type BIT, permit the use of single qoutes and also don't quote the default value.
		// For example, use DEFAULT b'1' as opposed to DEFAULT 'b\'1\'' which results in an error.
		else if ([[theRow objectForKey:@"Type"] isEqualToString:@"bit"]) {
			[queryString appendString:[NSString stringWithFormat:@" DEFAULT %@ ", [theRow objectForKey:@"Default"]]];
		}
		// Otherwise, use the provided default
		else {
			[queryString appendString:[NSString stringWithFormat:@" DEFAULT '%@' ", [mySQLConnection prepareString:[theRow objectForKey:@"Default"]]]];
		}
	}
	
	if (!(
			[[theRow objectForKey:@"Extra"] isEqualToString:@""] || 
			[[theRow objectForKey:@"Extra"] isEqualToString:@"None"]
		) && 
		[theRow objectForKey:@"Extra"] ) 
	{
		[queryString appendString:@" "];
		[queryString appendString:[theRow objectForKey:@"Extra"]];
	}
	
	if (!isEditingNewRow) {

		// Add details not provided via the SHOW COLUMNS query from the table data cache so column details aren't lost
		NSDictionary *originalColumnDetails = [[tableDataInstance columns] objectAtIndex:currentlyEditingRow];

		// Any column comments
		if ([originalColumnDetails objectForKey:@"comment"] && [[originalColumnDetails objectForKey:@"comment"] length]) {
			[queryString appendString:[NSString stringWithFormat:@" COMMENT '%@'", [mySQLConnection prepareString:[originalColumnDetails objectForKey:@"comment"]]]];
		}

		// Unparsed details - column formats, storage, reference definitions
		if ([originalColumnDetails objectForKey:@"unparsed"]) {
			[queryString appendString:[originalColumnDetails objectForKey:@"unparsed"]];
		}
	}
	
	// Asks the user to add an index to query if auto_increment is set and field isn't indexed
	if ([[theRow objectForKey:@"Extra"] isEqualToString:@"auto_increment"] && 
		([[theRow objectForKey:@"Key"] isEqualToString:@""] || 
		![theRow objectForKey:@"Key"])) 
	{
		[chooseKeyButton selectItemAtIndex:0];
		
		[NSApp beginSheet:keySheet 
		   modalForWindow:tableWindow modalDelegate:self 
		   didEndSelector:nil 
			  contextInfo:nil];
		
		code = [NSApp runModalForWindow:keySheet];
		
		[NSApp endSheet:keySheet];
		[keySheet orderOut:nil];
		
		if (code) {
			// User wants to add PRIMARY KEY
			if ([chooseKeyButton indexOfSelectedItem] == 0 ) { 
				[queryString appendString:@" PRIMARY KEY"];
				
				// Add AFTER ... only if the user added a new field
				if (isEditingNewRow) {
					[queryString appendString:[NSString stringWithFormat:@" AFTER %@", [[[tableFields objectAtIndex:(currentlyEditingRow -1)] objectForKey:@"Field"] backtickQuotedString]]];
				}
			} 
			else {
				// Add AFTER ... only if the user added a new field
				if (isEditingNewRow) {
					[queryString appendString:[NSString stringWithFormat:@" AFTER %@", [[[tableFields objectAtIndex:(currentlyEditingRow -1)] objectForKey:@"Field"] backtickQuotedString]]];
				} 
				
				[queryString appendString:[NSString stringWithFormat:@", ADD %@ (%@)", [chooseKeyButton titleOfSelectedItem], [[theRow objectForKey:@"Field"] backtickQuotedString]]];
			}
		}
	} 
	// Add AFTER ... only if the user added a new field
	else if (isEditingNewRow) {
		[queryString appendString:[NSString stringWithFormat:@" AFTER %@", [[[tableFields objectAtIndex:(currentlyEditingRow -1)] objectForKey:@"Field"] backtickQuotedString]]];
	}
	
	// Execute query
	[mySQLConnection queryString:queryString];

	if ([[mySQLConnection getLastErrorMessage] isEqualToString:@""]) {
		isEditingRow = NO;
		isEditingNewRow = NO;
		currentlyEditingRow = -1;
		
		[tableDataInstance resetAllData];
		[tablesListInstance setStatusRequiresReload:YES];
		[self loadTable:selectedTable];

		// Mark the content table for refresh
		[tablesListInstance setContentRequiresReload:YES];

		return YES;
	} 
	else {
		alertSheetOpened = YES;
		
		// Problem: alert sheet doesn't respond to first click
		if (isEditingNewRow) {
			NSBeginAlertSheet(NSLocalizedString(@"Error adding field", @"error adding field message"), 
							  NSLocalizedString(@"OK", @"OK button"), 
							  NSLocalizedString(@"Cancel", @"cancel button"), nil, tableWindow, self, @selector(sheetDidEnd:returnCode:contextInfo:), nil, @"addrow", 
							  [NSString stringWithFormat:NSLocalizedString(@"An error occurred when trying to add the field '%@'.\n\nMySQL said: %@", @"error adding field informative message"), 
							  [theRow objectForKey:@"Field"], [mySQLConnection getLastErrorMessage]]);
		} 
		else {
			NSBeginAlertSheet(NSLocalizedString(@"Error changing field", @"error changing field message"), 
							  NSLocalizedString(@"OK", @"OK button"), 
							  NSLocalizedString(@"Cancel", @"cancel button"), nil, tableWindow, self, @selector(sheetDidEnd:returnCode:contextInfo:), nil, @"addrow", 
							  [NSString stringWithFormat:NSLocalizedString(@"An error occurred when trying to change the field '%@'.\n\nMySQL said: %@", @"error changing field informative message"), 
							  [theRow objectForKey:@"Field"], [mySQLConnection getLastErrorMessage]]);
		}
		
		return NO;
	}
}

/*
 * Show Error sheet (can be called from inside of a endSheet selector)
 * via [self performSelector:@selector(showErrorSheetWithTitle:) withObject: afterDelay:]
 */
-(void)showErrorSheetWith:(id)error
{
	// error := first object is the title , second the message, only one button OK
	NSBeginAlertSheet([error objectAtIndex:0], NSLocalizedString(@"OK", @"OK button"), 
			nil, nil, tableWindow, self, nil, nil, nil,
			[error objectAtIndex:1]);
}

/**
 * This method is called as part of Key Value Observing which is used to watch for preference changes which effect the interface.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{	
	// Display table veiew vertical gridlines preference changed
	if ([keyPath isEqualToString:SPDisplayTableViewVerticalGridlines]) {
        [tableSourceView setGridStyleMask:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
		[indexView setGridStyleMask:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	}
	// Use monospaced fonts preference changed
	else if ([keyPath isEqualToString:SPUseMonospacedFonts]) {
		
		BOOL useMonospacedFont = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
		
		for (NSTableColumn *indexColumn in [indexView tableColumns])
		{
			[[indexColumn dataCell] setFont:(useMonospacedFont) ? [NSFont fontWithName:SPDefaultMonospacedFontName size:[NSFont smallSystemFontSize]] : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		}
		
		for (NSTableColumn *fieldColumn in [tableSourceView tableColumns])
		{
			[[fieldColumn dataCell] setFont:(useMonospacedFont) ? [NSFont fontWithName:SPDefaultMonospacedFontName size:[NSFont smallSystemFontSize]] : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		}
		
		[tableSourceView reloadData];
		[indexView reloadData];
	}
}

/**
 * Menu validation
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	// Remove field
	if ([menuItem action] == @selector(removeField:)) {
		return (([tableSourceView numberOfSelectedRows] == 1) && ([tableSourceView numberOfRows] > 1));
	}
	
	// Duplicate field
	if ([menuItem action] == @selector(copyField:)) {
		return ([tableSourceView numberOfSelectedRows] == 1);
	}
	
	// Remove index
	if ([menuItem action] == @selector(removeIndex:)) {
		return ([indexView numberOfSelectedRows] == 1);
	}
	
	return YES;
}

#pragma mark -
#pragma mark Alert sheet methods

/**
 * Called whenever a sheet is dismissed.
 *
 * if contextInfo == addrow: remain in edit-mode if user hits OK, otherwise cancel editing
 * if contextInfo == removefield: removes row from mysql-db if user hits ok
 * if contextInfo == removeindex: removes index from mysql-db if user hits ok
 * if contextInfo == addIndex: adds and index to the mysql-db if user hits ok
 * if contextInfo == cannotremovefield: do nothing
 */
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(NSString *)contextInfo
{	
	// Order out current sheet to suppress overlapping of sheets
	if ([sheet respondsToSelector:@selector(orderOut:)]) [sheet orderOut:nil];
	
	if ([contextInfo isEqualToString:@"addrow"]) {
		
		alertSheetOpened = NO;
		if ( returnCode == NSAlertDefaultReturn ) {
			
			// Problem: reentering edit mode for first cell doesn't function
			[tableSourceView editColumn:0 row:[tableSourceView selectedRow] withEvent:nil select:YES];
		} else {
			if ( !isEditingNewRow ) {
				[tableFields replaceObjectAtIndex:[tableSourceView selectedRow]
									   withObject:[NSMutableDictionary dictionaryWithDictionary:oldRow]];
				isEditingRow = NO;
			} else {
				[tableFields removeObjectAtIndex:[tableSourceView selectedRow]];
				isEditingRow = NO;
				isEditingNewRow = NO;
			}
			currentlyEditingRow = -1;
		}
		[tableSourceView reloadData];
	} 
	else if ([contextInfo isEqualToString:@"removeField"] || [contextInfo isEqualToString:@"removeFieldAndForeignKey"]) {
		if (returnCode == NSAlertDefaultReturn) {
			[self _removeFieldAndForeignKey:[contextInfo hasSuffix:@"AndForeignKey"]];
		}
	} 
	else if ([contextInfo isEqualToString:@"addIndex"]) {
		if (returnCode == NSOKButton) {
			[self _addIndex];
		}
	}
	else if ([contextInfo isEqualToString:@"removeIndex"] || [contextInfo isEqualToString:@"removeIndexAndForeignKey"]) {
		if (returnCode == NSAlertDefaultReturn) {
			[self _removeIndexAndForeignKey:[contextInfo hasSuffix:@"AndForeignKey"]];
		}
	} 
	else if ([contextInfo isEqualToString:@"cannotremovefield"]) {
		;
	}
}

#pragma mark -
#pragma mark Getter methods

/*
get the default value for a specified field
*/
- (NSString *)defaultValueForField:(NSString *)field
{
	if ( ![defaultValues objectForKey:field] ) {
		return [prefs objectForKey:SPNullValue];	
	} else if ( [[defaultValues objectForKey:field] isMemberOfClass:[NSNull class]] ) {
		return [prefs objectForKey:SPNullValue];
	} else {
		return [defaultValues objectForKey:field];
	}
}

/*
returns an array containing the field names of the selected table
*/
- (NSArray *)fieldNames
{
	NSMutableArray *tempArray = [NSMutableArray array];
	NSEnumerator *enumerator;
	id field;
	
	//load table if not already done
	if ( ![tablesListInstance structureLoaded] ) {
		[self loadTable:[tablesListInstance tableName]];
	}
	
	//get field names
	enumerator = [tableFields objectEnumerator];
	while ( (field = [enumerator nextObject]) ) {
		[tempArray addObject:[field objectForKey:@"Field"]];
	}
  
	return [NSArray arrayWithArray:tempArray];
}

/*
returns a dictionary containing enum/set field names as key and possible values as array
*/
- (NSDictionary *)enumFields
{
	return [NSDictionary dictionaryWithDictionary:enumFields];
}

- (NSArray *)tableStructureForPrint
{
	MCPResult *queryResult;
	NSMutableArray *tempResult = [NSMutableArray array];
	int i;
	
	queryResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM %@", [selectedTable backtickQuotedString]]];
	[queryResult setReturnDataAsStrings:YES];
	
	if ([queryResult numOfRows]) [queryResult dataSeek:0];
	[tempResult addObject:[queryResult fetchFieldNames]];
	for ( i = 0 ; i < [queryResult numOfRows] ; i++ ) {
		[tempResult addObject:[queryResult fetchRowAsArray]];
	}
	
	return tempResult;
}

#pragma mark -
#pragma mark Task interaction

/**
 * Disable all content interactive elements during an ongoing task.
 */
- (void) startDocumentTaskForTab:(NSNotification *)aNotification
{

	// Only proceed if this view is selected.
	if (![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableStructure])
		return;

	[tableSourceView setEnabled:NO];
	[addFieldButton setEnabled:NO];
	[removeFieldButton setEnabled:NO];
	[copyFieldButton setEnabled:NO];
	[reloadFieldsButton setEnabled:NO];
	[editTableButton setEnabled:NO];

	[indexView setEnabled:NO];
	[addIndexButton setEnabled:NO];
	[removeIndexButton setEnabled:NO];
	[reloadIndexesButton setEnabled:NO];
}

/**
 * Enable all content interactive elements after an ongoing task.
 */
- (void) endDocumentTaskForTab:(NSNotification *)aNotification
{

	// Only re-enable elements if the current tab is the structure view
	if (![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableStructure])
		return;

	BOOL editingEnabled = ([tablesListInstance tableType] == SP_TABLETYPE_TABLE);
	[tableSourceView setEnabled:YES];
	[tableSourceView displayIfNeeded];
	[addFieldButton setEnabled:editingEnabled];
	if (editingEnabled && [tableSourceView numberOfSelectedRows] > 0) {
		[removeFieldButton setEnabled:YES];
		[copyFieldButton setEnabled:YES];
	}
	[reloadFieldsButton setEnabled:YES];
	[editTableButton setEnabled:YES];

	[indexView setEnabled:YES];
	[indexView displayIfNeeded];
	[addIndexButton setEnabled:editingEnabled];
	if (editingEnabled && [indexView numberOfSelectedRows] > 0)
		[removeIndexButton setEnabled:YES];
	[reloadIndexesButton setEnabled:YES];
}

#pragma mark -
#pragma mark TableView datasource methods

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return (aTableView == tableSourceView) ? [tableFields count] : [indexes count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	NSDictionary *theRow;

	if (aTableView == tableSourceView) {
		
		// Return a placeholder if the table is reloading
		if (rowIndex >= [tableFields count]) return @"...";

		theRow = [tableFields objectAtIndex:rowIndex];
	} else {
		theRow = [indexes objectAtIndex:rowIndex];
	}

	return [theRow objectForKey:[aTableColumn identifier]];
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
    // Make sure that the drag operation is for the right table view
    if (aTableView!=tableSourceView) return;

	if (!isEditingRow) {
		[oldRow setDictionary:[tableFields objectAtIndex:rowIndex]];
		isEditingRow = YES;
		currentlyEditingRow = rowIndex;
	}
	
	[[tableFields objectAtIndex:rowIndex] setObject:(anObject) ? anObject : @"" forKey:[aTableColumn identifier]];
}

/*
Begin a drag and drop operation from the table - copy a single dragged row to the drag pasteboard.
*/
- (BOOL)tableView:(NSTableView *)tableView writeRows:(NSArray*)rows toPasteboard:(NSPasteboard*)pboard
{
    //make sure that the drag operation is started from the right table view
    if (tableView!=tableSourceView) return NO;
    
    
	int originalRow;
	NSArray *pboardTypes;

	// Check whether a save of the current field row is required.
	if ( ![self saveRowOnDeselect] ) return NO;

	if ( ([rows count] == 1)  && (tableView == tableSourceView) ) {
		pboardTypes=[NSArray arrayWithObjects:@"SequelProPasteboard", nil];
		originalRow = [[rows objectAtIndex:0] intValue];

		[pboard declareTypes:pboardTypes owner:nil];
		[pboard setString:[[NSNumber numberWithInt:originalRow] stringValue] forType:@"SequelProPasteboard"];

		return YES;
	} else {
		return NO;
	}
}

/*
Determine whether to allow a drag and drop operation on this table - for the purposes of drag reordering,
validate that the original source is of the correct type and within the same table, and that the drag
would result in a position change.
*/
- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row
	proposedDropOperation:(NSTableViewDropOperation)operation
{
    //make sure that the drag operation is for the right table view
    if (tableView!=tableSourceView) return NO;

	NSArray *pboardTypes = [[info draggingPasteboard] types];
	int originalRow;

	// Ensure the drop is of the correct type
	if (operation == NSTableViewDropAbove && row != -1 && [pboardTypes containsObject:@"SequelProPasteboard"]) {
	
		// Ensure the drag originated within this table
		if ([info draggingSource] == tableView) {
			originalRow = [[[info draggingPasteboard] stringForType:@"SequelProPasteboard"] intValue];
			
			if (row != originalRow && row != (originalRow+1)) {
				return NSDragOperationMove;
			}
		}
	}

	return NSDragOperationNone;
}

/*
 * Having validated a drop, perform the field/column reordering to match.
 */
- (BOOL)tableView:(NSTableView*)tableView acceptDrop:(id <NSDraggingInfo>)info row:(int)destinationRowIndex dropOperation:(NSTableViewDropOperation)operation
{
    //make sure that the drag operation is for the right table view
    if (tableView!=tableSourceView) return NO;

	int originalRowIndex;
	NSMutableString *queryString;
	NSDictionary *originalRow;

	// Extract the original row position from the pasteboard and retrieve the details
	originalRowIndex = [[[info draggingPasteboard] stringForType:@"SequelProPasteboard"] intValue];
	originalRow = [[NSDictionary alloc] initWithDictionary:[tableFields objectAtIndex:originalRowIndex]];

	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:tableDocumentInstance];

	// Begin construction of the reordering query
	queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ MODIFY COLUMN %@ %@", [selectedTable backtickQuotedString],
		[[originalRow objectForKey:@"Field"] backtickQuotedString],
		[originalRow objectForKey:@"Type"]];

	// Add the length parameter if necessary
	if ( [originalRow objectForKey:@"Length"] && ![[originalRow objectForKey:@"Length"] isEqualToString:@""]) {
		[queryString appendString:[NSString stringWithFormat:@"(%@)", [originalRow objectForKey:@"Length"]]];
	}

	// Add unsigned, zerofill, binary, not null if necessary
	if ([[originalRow objectForKey:@"unsigned"] isEqualToString:@"1"]) {
		[queryString appendString:@" UNSIGNED"];
	}
	if ([[originalRow objectForKey:@"zerofill"] isEqualToString:@"1"]) {
		[queryString appendString:@" ZEROFILL"];
	}
	if ([[originalRow objectForKey:@"binary"] isEqualToString:@"1"]) {
		[queryString appendString:@" BINARY"];
	}
	if ([[originalRow objectForKey:@"Null"] isEqualToString:@"0"] ) {
		[queryString appendString:@" NOT NULL"];
	}
	if (![[originalRow objectForKey:@"Extra"] isEqualToString:@"None"] ) {
		[queryString appendString:@" "];
		[queryString appendString:[[originalRow objectForKey:@"Extra"] uppercaseString]];
	}

	// Add the default value
	if ([[originalRow objectForKey:@"Default"] isEqualToString:[prefs objectForKey:SPNullValue]]) {
		if ([[originalRow objectForKey:@"Null"] intValue] == 1) {
			[queryString appendString:@" DEFAULT NULL"];
		}
	} else if ( [[originalRow objectForKey:@"Type"] isEqualToString:@"timestamp"] && ([[[originalRow objectForKey:@"Default"] uppercaseString] isEqualToString:@"CURRENT_TIMESTAMP"]) ) {
			[queryString appendString:@" DEFAULT CURRENT_TIMESTAMP"];
	} else {
		[queryString appendString:[NSString stringWithFormat:@" DEFAULT '%@'", [mySQLConnection prepareString:[originalRow objectForKey:@"Default"]]]];
	}

	// Add details not provided via the SHOW COLUMNS query from the table data cache so column details aren't lost
	NSDictionary *originalColumnDetails = [[tableDataInstance columns] objectAtIndex:originalRowIndex];

	// Any column comments
	if ([originalColumnDetails objectForKey:@"comment"] && [[originalColumnDetails objectForKey:@"comment"] length]) {
		[queryString appendString:[NSString stringWithFormat:@" COMMENT '%@'", [mySQLConnection prepareString:[originalColumnDetails objectForKey:@"comment"]]]];
	}

	// Unparsed details - column formats, storage, reference definitions
	if ([originalColumnDetails objectForKey:@"unparsed"]) {
		[queryString appendString:[originalColumnDetails objectForKey:@"unparsed"]];
	}

	// Add the new location
	if ( destinationRowIndex == 0 ){
		[queryString appendString:@" FIRST"];
	} else {
		[queryString appendString:[NSString stringWithFormat:@" AFTER %@",
						[[[tableFields objectAtIndex:destinationRowIndex-1] objectForKey:@"Field"] backtickQuotedString]]];
	}

	// Run the query; report any errors, or reload the table on success
	[mySQLConnection queryString:queryString];
	if ( ![[mySQLConnection getLastErrorMessage] isEqualTo:@""] ) {
		NSBeginAlertSheet(NSLocalizedString(@"Error", @"error"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil,
			[NSString stringWithFormat:NSLocalizedString(@"Couldn't move field. MySQL said: %@", @"message of panel when field cannot be added in drag&drop operation"), [mySQLConnection getLastErrorMessage]]);
	} else {
		[tableDataInstance resetAllData];
		[tablesListInstance setStatusRequiresReload:YES];
		[self loadTable:selectedTable];

		// Mark the content table cache for refresh
		[tablesListInstance setContentRequiresReload:YES];

		if ( originalRowIndex < destinationRowIndex ) {
			[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:destinationRowIndex-1] byExtendingSelection:NO];
		} else {
			[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:destinationRowIndex] byExtendingSelection:NO];
		}
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];
	
	[originalRow release];
	return YES;
}

#pragma mark -
#pragma mark TableView delegate methods

/**
 * Performs various interface validation
 */
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	id object = [aNotification object];
	
	// Check for which table view the selection changed
	if (object == tableSourceView) {
		// If we are editing a row, attempt to save that row - if saving failed, reselect the edit row.
		if (isEditingRow && [tableSourceView selectedRow] != currentlyEditingRow) {
			[self saveRowOnDeselect];
			isEditingRow = NO;
		}
		
		[copyFieldButton setEnabled:YES];

		// Check if there is currently a field selected and change button state accordingly
		if ([tableSourceView numberOfSelectedRows] > 0 && [tablesListInstance tableType] == SP_TABLETYPE_TABLE) {
			[removeFieldButton setEnabled:YES];
		} else {
			[removeFieldButton setEnabled:NO];
			[copyFieldButton setEnabled:NO];
		}
		
		// If the table only has one field, disable the remove button. This removes the need to check that the user
		// is attempting to remove the last field in a table in removeField: above, but leave it in just in case.
		if ([tableSourceView numberOfRows] == 1) {
			[removeFieldButton setEnabled:NO];
		}
	}
	else if (object == indexView) {
		// Check if there is currently an index selected and change button state accordingly
		[removeIndexButton setEnabled:([indexView numberOfSelectedRows] > 0 && [tablesListInstance tableType] == SP_TABLETYPE_TABLE)];
	}
}

/**
 * Traps enter and esc and make/cancel editing without entering next row
 */
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	int row, column;

	row = [tableSourceView editedRow];
	column = [tableSourceView editedColumn];

	 if (  [textView methodForSelector:command] == [textView methodForSelector:@selector(insertNewline:)] ||
				[textView methodForSelector:command] == [textView methodForSelector:@selector(insertTab:)] ) //trap enter and tab
	 {
		//save current line
		[[control window] makeFirstResponder:control];
		if ( column == 9 ) {
			if ( [self addRowToDB] && [textView methodForSelector:command] == [textView methodForSelector:@selector(insertTab:)] ) {
				if ( row < ([tableSourceView numberOfRows] - 1) ) {
					[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:row+1] byExtendingSelection:NO];
					[tableSourceView editColumn:0 row:row+1 withEvent:nil select:YES];
				} else {
					[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
					[tableSourceView editColumn:0 row:0 withEvent:nil select:YES];
				}
			}
		} else {
			if ( column == 2 ) {
				[tableSourceView editColumn:column+6 row:row withEvent:nil select:YES];
			} else {
				[tableSourceView editColumn:column+1 row:row withEvent:nil select:YES];
			}
		}
		return TRUE;
		 
	 } else if (  [[control window] methodForSelector:command] == [[control window] methodForSelector:@selector(_cancelKey:)] ||
					[textView methodForSelector:command] == [textView methodForSelector:@selector(complete:)] ) {
		//abort editing
		[control abortEditing];
		if ( isEditingRow && !isEditingNewRow ) {
			isEditingRow = NO;
			[tableFields replaceObjectAtIndex:row withObject:[NSMutableDictionary dictionaryWithDictionary:oldRow]];
		} else if ( isEditingNewRow ) {
			isEditingRow = NO;
			isEditingNewRow = NO;
			[tableFields removeObjectAtIndex:row];
			[tableSourceView reloadData];
		}
		currentlyEditingRow = -1;
		return TRUE;
	 } else {
		 return FALSE;
	 }
}


/*
 * Modify cell display by disabling table cells when a view is selected, meaning structure/index
 * is uneditable.
 */
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex {
    
    //make sure that the message is from the right table view
    if (tableView!=tableSourceView) return;

	[aCell setEnabled:([tablesListInstance tableType] == SP_TABLETYPE_TABLE)];
}

#pragma mark -
#pragma mark SplitView delegate methods

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
	return YES;
}

- (float)splitView:(NSSplitView *)sender constrainMaxCoordinate:(float)proposedMax ofSubviewAt:(int)offset
{
	return proposedMax - 150;
}

- (float)splitView:(NSSplitView *)sender constrainMinCoordinate:(float)proposedMin ofSubviewAt:(int)offset
{
	return proposedMin + 150;
}

- (NSRect)splitView:(NSSplitView *)splitView additionalEffectiveRectOfDividerAtIndex:(int)dividerIndex
{	
	return [structureGrabber convertRect:[structureGrabber bounds] toView:splitView];
}

#pragma mark -
#pragma mark Other

// Last but not least
- (id)init
{
	if ((self = [super init])) {
		tableFields = [[NSMutableArray alloc] init];
		indexes     = [[NSMutableArray alloc] init];
		oldRow      = [[NSMutableDictionary alloc] init];
		enumFields  = [[NSMutableDictionary alloc] init];
		
		currentlyEditingRow = -1;
		defaultValues = nil;
		selectedTable = nil;
		
		prefs = [NSUserDefaults standardUserDefaults];
	}

	return self;
}

- (void)awakeFromNib
{
	// Set the structure and index view's vertical gridlines if required
	[tableSourceView setGridStyleMask:([prefs boolForKey:SPDisplayTableViewVerticalGridlines]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	[indexView setGridStyleMask:([prefs boolForKey:SPDisplayTableViewVerticalGridlines]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
		
	// Set the strutcture and index view's font
	BOOL useMonospacedFont = [prefs boolForKey:SPUseMonospacedFonts];
	
	for (NSTableColumn *indexColumn in [indexView tableColumns])
	{
		[[indexColumn dataCell] setFont:(useMonospacedFont) ? [NSFont fontWithName:SPDefaultMonospacedFontName size:[NSFont smallSystemFontSize]] : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	}
	
	for (NSTableColumn *fieldColumn in [tableSourceView tableColumns])
	{
		[[fieldColumn dataCell] setFont:(useMonospacedFont) ? [NSFont fontWithName:SPDefaultMonospacedFontName size:[NSFont smallSystemFontSize]] : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	}
	
	// Add observers for document task activity
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(startDocumentTaskForTab:)
												 name:SPDocumentTaskStartNotification
											   object:tableDocumentInstance];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(endDocumentTaskForTab:)
												 name:SPDocumentTaskEndNotification
											   object:tableDocumentInstance];
}

- (void)dealloc
{	
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[tableFields release];
	[indexes release];
	[oldRow release];
	[enumFields release];
	if (defaultValues) [defaultValues release];
	if (selectedTable) [selectedTable release];
	
	[super dealloc];
}

@end

@implementation TableSource (PrivateAPI)

/**
 * Adds an index to the current table.
 */
- (IBAction)_addIndex;
{
	NSString *indexName;
	NSArray *indexedColumns;
	NSMutableArray *tempIndexedColumns = [NSMutableArray array];
	NSString *string;
	
	// Check whether a save of the current fields row is required.
	if (![self saveRowOnDeselect]) return;
	
	if (![[indexedColumnsField stringValue] isEqualToString:@""]) {
		
		if ([[indexNameField stringValue] isEqualToString:@"PRIMARY"]) {
			indexName = @"";
		} 
		else {
			indexName = ([[indexNameField stringValue] isEqualToString:@""]) ? @"" : [[indexNameField stringValue] backtickQuotedString];
		}
		
		indexedColumns = [[indexedColumnsField stringValue] componentsSeparatedByString:@","];
		
		NSEnumerator *enumerator = [indexedColumns objectEnumerator];
		
		while ((string = [enumerator nextObject])) 
		{
			if (([string characterAtIndex:0] == ' ')) {
				[tempIndexedColumns addObject:[string substringWithRange:NSMakeRange(1, ([string length] - 1))]];
			} 
			else {
				[tempIndexedColumns addObject:[NSString stringWithString:string]];
			}
		}
		
		// Execute the query
		[mySQLConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ ADD %@ %@ (%@)",
									  [selectedTable backtickQuotedString], [indexTypeField titleOfSelectedItem], indexName,
									  [tempIndexedColumns componentsJoinedAndBacktickQuoted]]];
		
		// Check for errors
		if ([[mySQLConnection getLastErrorMessage] isEqualToString:@""]) {
			[tableDataInstance resetAllData];
			[tablesListInstance setStatusRequiresReload:YES];
			[self loadTable:selectedTable];
		}
		else {
			NSBeginAlertSheet(NSLocalizedString(@"Unable to add index", @"add index error message"), NSLocalizedString(@"OK", @"OK button"), nil, nil, tableWindow, self, nil, nil, nil, 
							  [NSString stringWithFormat:NSLocalizedString(@"An error occured while trying to add the index.\n\nMySQL said: %@", @"add index error informative message"), [mySQLConnection getLastErrorMessage]]);
		}
	}
}

/**
 * Removes a field from the current table and the dependent foreign key if specified. 
 */
- (void)_removeFieldAndForeignKey:(BOOL)removeForeignKey
{
	// Remove the foreign key before the field if required
	if (removeForeignKey) {
		
		NSString *relationName = @"";
		NSString *field = [[tableFields objectAtIndex:[tableSourceView selectedRow]] objectForKey:@"Field"];
		
		// Get the foreign key name
		for (NSDictionary *constraint in [tableDataInstance getConstraints])
		{
			for (NSString *column in [constraint objectForKey:@"columns"])
			{
				if ([column isEqualToString:field]) {
					relationName = [constraint objectForKey:@"name"];
					break;
				}
			}
		}
		
		[mySQLConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ DROP FOREIGN KEY %@", [selectedTable backtickQuotedString], [relationName backtickQuotedString]]];
		
		if (![[mySQLConnection getLastErrorMessage] isEqualToString:@""]) {
			
			NSBeginAlertSheet(NSLocalizedString(@"Unable to remove relation", @"error removing relation message"), 
							  NSLocalizedString(@"OK", @"OK button"),
							  nil, nil, [NSApp mainWindow], nil, nil, nil, nil, 
							  [NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to remove the relation '%@'.\n\nMySQL said: %@", @"error removing relation informative message"), relationName, [mySQLConnection getLastErrorMessage]]);	
		} 
	}
	
	// Remove field
	[mySQLConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ DROP %@",
								  [selectedTable backtickQuotedString], [[[tableFields objectAtIndex:[tableSourceView selectedRow]] objectForKey:@"Field"] backtickQuotedString]]];
	
	if ([[mySQLConnection getLastErrorMessage] isEqualToString:@""]) {
		[tableDataInstance resetAllData];
		[tablesListInstance setStatusRequiresReload:YES];
		[self loadTable:selectedTable];
		
		// Mark the content table cache for refresh
		[tablesListInstance setContentRequiresReload:YES];
	} 
	else {
		[self performSelector:@selector(showErrorSheetWith:) 
				   withObject:[NSArray arrayWithObjects:NSLocalizedString(@"Error", @"error"),
							   [NSString stringWithFormat:NSLocalizedString(@"Couldn't remove field %@.\nMySQL said: %@", @"message of panel when field cannot be removed"),
								[[tableFields objectAtIndex:[tableSourceView selectedRow]] objectForKey:@"Field"],
								[mySQLConnection getLastErrorMessage]],
							   nil] 
				   afterDelay:0.3];
	}
}

/**
 * Removes an index from the current table and the dependent foreign key if specified.
 */
- (void)_removeIndexAndForeignKey:(BOOL)removeForeignKey
{
	// Remove the foreign key dependency before the index if required
	if (removeForeignKey) {
		
		NSString *columnName =  [[indexes objectAtIndex:[indexView selectedRow]] objectForKey:@"Column_name"];
		
		NSString *constraintName = @"";
		
		// Check to see whether the user is attempting to remove an index that a foreign key constraint depends on
		// thus would result in an error if not dropped before removing the index.
		for (NSDictionary *constraint in [tableDataInstance getConstraints])
		{
			for (NSString *column in [constraint objectForKey:@"columns"])
			{
				if ([column isEqualToString:columnName]) {
					constraintName = [constraint objectForKey:@"name"];
					break;
				}
			}
		}
		
		[mySQLConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ DROP FOREIGN KEY %@", [selectedTable backtickQuotedString], [constraintName backtickQuotedString]]];
		
		if (![[mySQLConnection getLastErrorMessage] isEqualToString:@""] ) {
			
			NSBeginAlertSheet(NSLocalizedString(@"Unable to remove relation", @"error removing relation message"), 
							  NSLocalizedString(@"OK", @"OK button"),
							  nil, nil, [NSApp mainWindow], nil, nil, nil, nil, 
							  [NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to remove the relation '%@'.\n\nMySQL said: %@", @"error removing relation informative message"), constraintName, [mySQLConnection getLastErrorMessage]]);	
		} 
	}
	
	if ([[[indexes objectAtIndex:[indexView selectedRow]] objectForKey:@"Key_name"] isEqualToString:@"PRIMARY"]) {
		[mySQLConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ DROP PRIMARY KEY", [selectedTable backtickQuotedString]]];
	}
	else {
		[mySQLConnection queryString:[NSString stringWithFormat:@"ALTER TABLE %@ DROP INDEX %@",
									  [selectedTable backtickQuotedString], [[[indexes objectAtIndex:[indexView selectedRow]] objectForKey:@"Key_name"] backtickQuotedString]]];
	}
	
	// Check for errors
	if ([[mySQLConnection getLastErrorMessage] isEqualToString:@""]) {
		[tableDataInstance resetAllData];
		[tablesListInstance setStatusRequiresReload:YES];
		[self loadTable:selectedTable];
	} 
	else {
		[self performSelector:@selector(showErrorSheetWith:) 
				   withObject:[NSArray arrayWithObjects:NSLocalizedString(@"Unable to remove index", @"error removing index message"),
							   [NSString stringWithFormat:NSLocalizedString(@"An error occured while trying to remove the index.\n\nMySQL said: %@", @"error removing index informative message"), [mySQLConnection getLastErrorMessage]], nil] 
				   afterDelay:0.3];
	}
}

@end
