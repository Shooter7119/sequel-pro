//
//  SPTableTriggers.m
//  sequel-pro
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

#import "SPTableTriggers.h"
#import "TableDocument.h"
#import "TablesList.h"
#import "SPTableData.h"
#import "SPStringAdditions.h"
#import "SPConstants.h"
#import "SPAlertSheets.h"

@interface SPTableTriggers (PrivateAPI)

- (void)_toggleConfirmAddTriggerButtonEnabled;
- (void)_refreshTriggerDataForcingCacheRefresh:(BOOL)clearAllCaches;

@end

@implementation SPTableTriggers

@synthesize connection;

/**
 * init
 */
- (id)init
{
	if ((self = [super init])) {
		triggerData = [[NSMutableArray alloc] init];
	}
	
	return self;
}

/**
 * Register to listen for table selection changes upon nib awakening.
 */
- (void)awakeFromNib
{
	// Set the table triggers view's vertical gridlines if required
	[triggersTableView setGridStyleMask:([[NSUserDefaults standardUserDefaults] boolForKey:SPDisplayTableViewVerticalGridlines]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	
	// Set the strutcture and index view's font
	BOOL useMonospacedFont = [[NSUserDefaults standardUserDefaults] boolForKey:SPUseMonospacedFonts];
	
	for (NSTableColumn *column in [triggersTableView tableColumns])
	{
		[[column dataCell] setFont:(useMonospacedFont) ? [NSFont fontWithName:SPDefaultMonospacedFontName size:[NSFont smallSystemFontSize]] : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	}
	
	// Register as an observer for the when the UseMonospacedFonts preference changes
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:SPUseMonospacedFonts options:NSKeyValueObservingOptionNew context:NULL];

	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(triggerStatementTextDidChange:) 
												 name:NSTextStorageDidProcessEditingNotification 
											   object:[triggerStatementTextView textStorage]];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(tableSelectionChanged:) 
												 name:SPTableChangedNotification 
											   object:tableDocumentInstance];
	
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

#pragma mark -
#pragma mark IB action methods

/**
 * Closes the trigers sheet.
 */
- (IBAction)closeTriggerSheet:(id)sender
{
	[NSApp endSheet:addTriggerPanel returnCode:0];
	[addTriggerPanel orderOut:self];
}

/**
 * Add a new trigger using the selected values.
 */
- (IBAction)confirmAddTrigger:(id)sender
{	
	[self closeTriggerSheet:self];
	
	NSString *triggerName        = [triggerNameTextField stringValue];
	NSString *triggerActionTime  = [[triggerActionTimePopUpButton titleOfSelectedItem] uppercaseString];
	NSString *triggerEvent       = [[triggerEventPopUpButton titleOfSelectedItem] uppercaseString];
	NSString *triggerStatement   = [triggerStatementTextView string];
	
	NSString *query = [NSString stringWithFormat:@"CREATE TRIGGER %@ %@ %@ ON %@ FOR EACH ROW %@", 
					   [triggerName backtickQuotedString],
					   triggerActionTime,
					   triggerEvent,
					   [[tablesListInstance tableName] backtickQuotedString],
					   triggerStatement];
	
	// Execute query
	[connection queryString:query];
	
	NSInteger retCode = (![[connection getLastErrorMessage] isEqualToString:@""]);
	
	// 0 indicates success
	if (retCode) {
		SPBeginAlertSheet(NSLocalizedString(@"Error creating trigger", @"error creating trigger message"), 
						  NSLocalizedString(@"OK", @"OK button"),
						  nil, nil, [NSApp mainWindow], nil, nil, nil, nil, 
						  [NSString stringWithFormat:NSLocalizedString(@"The specified trigger was unable to be created.\n\nMySQL said: %@", @"error creating trigger informative message"), [connection getLastErrorMessage]]);		
	} 
	else {
		[self _refreshTriggerDataForcingCacheRefresh:YES];
	}
}

/**
 * Called whenever the user selected to add a new trigger. 
 */
- (IBAction)addTrigger:(id)sender
{			
	[NSApp beginSheet:addTriggerPanel
	   modalForWindow:tableWindow
		modalDelegate:self
	   didEndSelector:nil 
		  contextInfo:nil];
}

/**
 * Removes the selected trigger.
 */
- (IBAction)removeTrigger:(id)sender
{
	if ([triggersTableView numberOfSelectedRows] > 0) {
		
		NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Delete trigger", @"delete trigger message") 
										 defaultButton:NSLocalizedString(@"Delete", @"delete button") 
									   alternateButton:NSLocalizedString(@"Cancel", @"cancel button")
										   otherButton:nil 
							 informativeTextWithFormat:NSLocalizedString(@"Are you sure you want to delete the selected triggers? This action cannot be undone.", @"delete selected trigger informative message")];
		
		[alert setAlertStyle:NSCriticalAlertStyle];
		
		NSArray *buttons = [alert buttons];
		
		// Change the alert's cancel button to have the key equivalent of return
		[[buttons objectAtIndex:0] setKeyEquivalent:@"d"];
		[[buttons objectAtIndex:0] setKeyEquivalentModifierMask:NSCommandKeyMask];
		[[buttons objectAtIndex:1] setKeyEquivalent:@"\r"];
		
		[alert beginSheetModalForWindow:tableWindow modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:@"removeTrigger"];
	}
}

/**
 * Trigger a refresh of the displayed relations via the interface.
 */
- (IBAction)refreshTriggers:(id)sender
{
	[self _refreshTriggerDataForcingCacheRefresh:YES];
}

/**
 * Called whenever the user selects a different table.
 */
- (void)tableSelectionChanged:(NSNotification *)notification
{
	[labelTextField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Triggers for table: %@", @"triggers for table label"), [tablesListInstance tableName]]];
	
	BOOL enableInteraction = ((![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableTriggers]) || (![tableDocumentInstance isWorking]));
	
	// To begin enable all interface elements
	[addTriggerButton setEnabled:enableInteraction];		
	[refreshTriggersButton setEnabled:enableInteraction];
	[triggersTableView setEnabled:YES];	
	
	[self _refreshTriggerDataForcingCacheRefresh:NO];
}

#pragma mark -
#pragma mark Tableview datasource methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [triggerData count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	return [[triggerData objectAtIndex:rowIndex] objectForKey:[tableColumn identifier]];
}

#pragma mark -
#pragma mark Tableview delegate methods

/**
 * Called whenever the triggers table view selection changes.
 */
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[removeTriggerButton setEnabled:([triggersTableView numberOfSelectedRows] > 0)];
}

/*
 * Double-click action on table cells - for the time being, return
 * NO to disable editing.
 */
- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if ([tableDocumentInstance isWorking]) return NO;
	
	return NO;
}

/**
 * Disable row selection while the document is working.
 */
- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
	return (![tableDocumentInstance isWorking]);
}

#pragma mark -
#pragma mark Task interaction

/**
 * Disable all content interactive elements during an ongoing task.
 */
- (void)startDocumentTaskForTab:(NSNotification *)notification
{	
	// Only proceed if this view is selected.
	if (![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableTriggers]) return;
	
	[addTriggerButton setEnabled:NO];
	[refreshTriggersButton setEnabled:NO];
	[removeTriggerButton setEnabled:NO];
}

/**
 * Enable all content interactive elements after an ongoing task.
 */
- (void)endDocumentTaskForTab:(NSNotification *)notification
{		
	// Only proceed if this view is selected.
	if (![[tableDocumentInstance selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarTableTriggers]) return;
	
	if ([triggersTableView isEnabled]) {
		[addTriggerButton setEnabled:YES];
		[refreshTriggersButton setEnabled:YES];
	}
	
	[removeTriggerButton setEnabled:([triggersTableView numberOfSelectedRows] > 0)];
}

#pragma mark -
#pragma mark Other

/**
 * NSAlert didEnd method.
 */
- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo
{
	if ([contextInfo isEqualToString:@"removeTrigger"]) {
		
		if (returnCode == NSAlertDefaultReturn) {
			
			NSString *database = [tableDocumentInstance database];
			NSIndexSet *selectedSet = [triggersTableView selectedRowIndexes];
			
			NSUInteger row = [selectedSet lastIndex];
			
			while (row != NSNotFound) 
			{
				NSString *triggerName = [[triggerData objectAtIndex:row] objectForKey:@"trigger"];
				NSString *query = [NSString stringWithFormat:@"DROP TRIGGER %@.%@", [database backtickQuotedString], [triggerName backtickQuotedString]];
				
				[connection queryString:query];
				
				if (![[connection getLastErrorMessage] isEqualToString:@""] ) {
					
					SPBeginAlertSheet(NSLocalizedString(@"Unable to remove trigger", @"error removing trigger message"), 
									  NSLocalizedString(@"OK", @"OK button"),
									  nil, nil, [NSApp mainWindow], nil, nil, nil, nil, 
									  [NSString stringWithFormat:NSLocalizedString(@"The selected trigger couldn't be removed.\n\nMySQL said: %@", @"error removing trigger informative message"), [connection getLastErrorMessage]]);	
					
					// Abort loop
					break;
				} 
				
				row = [selectedSet indexLessThanIndex:row];
			}
			
			[self _refreshTriggerDataForcingCacheRefresh:YES];
		}
	} 
}

/**
 * This method is called as part of Key Value Observing which is used to watch for prefernce changes which effect the interface.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{	
	// Display table veiew vertical gridlines preference changed
	if ([keyPath isEqualToString:SPDisplayTableViewVerticalGridlines]) {
        [triggersTableView setGridStyleMask:([[change objectForKey:NSKeyValueChangeNewKey] boolValue]) ? NSTableViewSolidVerticalGridLineMask : NSTableViewGridNone];
	}
	// Use monospaced fonts preference changed
	else if ([keyPath isEqualToString:SPUseMonospacedFonts]) {
		
		BOOL useMonospacedFont = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
		
		for (NSTableColumn *column in [triggersTableView tableColumns])
		{
			[[column dataCell] setFont:(useMonospacedFont) ? [NSFont fontWithName:SPDefaultMonospacedFontName size:[NSFont smallSystemFontSize]] : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		}
		
		[triggersTableView reloadData];
	}
}

/**
 * Menu validation
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	// Remove row
	if ([menuItem action] == @selector(removeTrigger:)) {
		[menuItem setTitle:([triggersTableView numberOfSelectedRows] > 1) ? NSLocalizedString(@"Delete Triggers", @"delete triggers menu item") : NSLocalizedString(@"Delete Trigger", @"delete trigger menu item")];
		
		return ([triggersTableView numberOfSelectedRows] > 0);
	}
	
	return YES;
}

/**
 * 
 */
- (void)controlTextDidChange:(NSNotification *)notification
{	
	[self _toggleConfirmAddTriggerButtonEnabled];
}

/**
 * 
 */
- (void)triggerStatementTextDidChange:(NSNotification *)notification
{
	[self _toggleConfirmAddTriggerButtonEnabled];
}

#pragma mark -

/*
 * Dealloc.
 */
- (void)dealloc
{	
	[triggerData release], triggerData = nil;
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[super dealloc];
}

@end

@implementation SPTableTriggers (PrivateAPI)

/**
 * Enables or disables the confirm add trigger button based on the values of the trigger's name
 * and statement fields.
 */
- (void)_toggleConfirmAddTriggerButtonEnabled
{
	[confirmAddTriggerButton setEnabled:(([[triggerNameTextField stringValue] length] > 0) && ([[triggerStatementTextView string] length] > 0))];
}

/**
 * Refresh the displayed trigger, optionally forcing a refresh of the underlying cache.
 */
- (void)_refreshTriggerDataForcingCacheRefresh:(BOOL)clearAllCaches
{
	[triggerData removeAllObjects];
	
	if ([tablesListInstance tableType] == SP_TABLETYPE_TABLE) {
		
		if (clearAllCaches) [tableDataInstance updateInformationForCurrentTable];
		
		NSArray *triggers = [tableDataInstance triggers];
		
		for (NSDictionary *trigger in triggers) 
		{
			[triggerData addObject:[NSDictionary dictionaryWithObjectsAndKeys:
									 [trigger objectForKey:@"Table"], @"table",
									 [trigger objectForKey:@"Trigger"], @"trigger",
									 [trigger objectForKey:@"Event"], @"event",
									 [trigger objectForKey:@"Timing"], @"timing",
									 [trigger objectForKey:@"Statement"], @"statement",
 									 [trigger objectForKey:@"Definer"], @"definer",
									 [trigger objectForKey:@"Created"], @"created",
									 [trigger objectForKey:@"sql_mode"], @"sql_mode",
									 nil]];
			
		}		
	} 
	
	[triggersTableView reloadData];
}

@end
