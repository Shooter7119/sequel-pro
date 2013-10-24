//
//  $Id: SPWindowController.m 3745 2012-07-25 10:18:02Z stuart02 $
//
//  SPWindowController.m
//  sequel-pro
//
//  Created by Rowan Beentje on May 16, 2010.
//  Copyright (c) 2010 Rowan Beentje. All rights reserved.
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

// Forward-declare for 10.7 compatibility
#if !defined(MAC_OS_X_VERSION_10_7) || MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_7
enum {
	NSWindowCollectionBehaviorFullScreenPrimary = 1 << 7,
	NSWindowCollectionBehaviorFullScreenAuxiliary = 1 << 8
};
#endif

#import "SPWindowController.h"
#import "SPDatabaseDocument.h"
#import "SPDatabaseViewController.h"
#import "SPAppController.h"
#import "PSMTabDragAssistant.h"

#import <PSMTabBar/PSMTabBarControl.h>
#import <PSMTabBar/PSMTabStyle.h>

@interface SPWindowController ()

- (void)_updateProgressIndicatorForItem:(NSTabViewItem *)theItem;

@end

@implementation SPWindowController

/**
 * awakeFromNib
 */
- (void)awakeFromNib
{
	selectedTableDocument = nil;

	[[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorFullScreenPrimary];

	// Disable automatic cascading - this occurs before the size is set, so let the app
	// controller apply cascading after frame autosaving.
	[self setShouldCascadeWindows:NO];

	// Initialise the managed database connections array
	managedDatabaseConnections = [[NSMutableArray alloc] init];

	// Set up the tab bar
	[tabBar setStyleNamed:@"SequelPro"];
	[tabBar setCanCloseOnlyTab:NO];
	[tabBar setHideForSingleTab:![[NSUserDefaults standardUserDefaults] boolForKey:SPAlwaysShowWindowTabBar]];
	[tabBar setShowAddTabButton:YES];
	[tabBar setSizeCellsToFit:NO];
	[tabBar setCellMinWidth:100];
	[tabBar setCellMaxWidth:250];
	[tabBar setCellOptimumWidth:250];
	[tabBar setSelectsTabsOnMouseDown:YES];
	[tabBar setCreatesTabOnDoubleClick:YES];
	[tabBar setTearOffStyle:PSMTabBarTearOffAlphaWindow];
	[tabBar setUsesSafariStyleDragging:YES];

    // Hook up add tab button
    [tabBar setCreateNewTabTarget:self];
    [tabBar setCreateNewTabAction:@selector(addNewConnection:)];
	
	// Set the double click target and action
	[tabBar setDoubleClickTarget:self];
	[tabBar setDoubleClickAction:@selector(openDatabaseInNewTab)];

	// Retrieve references to the 'Close Window' and 'Close Tab' menus.  These are updated as window focus changes.
	closeWindowMenuItem = [[[[NSApp mainMenu] itemWithTag:SPMainMenuFile] submenu] itemWithTag:1003];
	closeTabMenuItem = [[[[NSApp mainMenu] itemWithTag:SPMainMenuFile] submenu] itemWithTag:1103];

	// Register for drag start and stop notifications - used to show/hide tab bars
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tabDragStarted:) name:PSMTabDragDidBeginNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tabDragStopped:) name:PSMTabDragDidEndNotification object:nil];
}

/**
 * Deallocation
 */
- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	// Tear down the animations on the tab bar to stop redraws
	[tabBar destroyAnimations];
	
	[managedDatabaseConnections release];

	[super dealloc];
}

#pragma mark -
#pragma mark Database connection management

/**
 * Add a new database connection to the window, in a tab view.
 */
- (IBAction)addNewConnection:(id)sender
{
	// Create a new database connection view
	SPDatabaseDocument *newTableDocument = [[SPDatabaseDocument alloc] init];
	[newTableDocument setParentWindowController:self];
	[newTableDocument setParentWindow:[self window]];

	// Set up a new tab with the connection view as the identifier, add the view, and add it to the tab view
    NSTabViewItem *newItem = [[[NSTabViewItem alloc] initWithIdentifier:newTableDocument] autorelease];
	[newItem setView:[newTableDocument databaseView]];
    [tabView addTabViewItem:newItem];
    [tabView selectTabViewItem:newItem];
	[newTableDocument setParentTabViewItem:newItem];

	// Tell the new database connection view to set up the window and update titles
	[newTableDocument didBecomeActiveTabInWindow];
	[newTableDocument updateWindowTitle:self];

	// Bind the tab bar's progress display to the document
	[self _updateProgressIndicatorForItem:newItem];

	[newTableDocument release];
}

/**
 * Retrieve the currently connection view in the window.
 */
- (SPDatabaseDocument *) selectedTableDocument
{
	return selectedTableDocument;
}

/**
 * Update the currently selected connection view
 */
- (void) updateSelectedTableDocument
{
	selectedTableDocument = [[tabView selectedTabViewItem] identifier];
	[selectedTableDocument didBecomeActiveTabInWindow];
}

/**
 * Ask all the connection views to update their titles.
 * As tab titles depend on the currently selected tab, changes
 * within each tab may require other tabs to update their titles.
 * If the sender is a tab, that tab is skipped when updating titles.
 */
- (void) updateAllTabTitles:(id)sender
{
	for (NSTabViewItem *eachItem in [tabView tabViewItems]) {
		SPDatabaseDocument *eachDocument = [eachItem identifier];
		if (eachDocument != sender) [eachDocument updateWindowTitle:self];
	}
}


/**
 * Close the current tab, or if it's the last in the window, the window.
 */
- (IBAction) closeTab:(id)sender
{
	// Return if the selected tab shouldn't be closed
	if (![selectedTableDocument parentTabShouldClose]) return;

	// If there are multiple tabs, close the front tab.
	if ([tabView numberOfTabViewItems] > 1) {
		[tabView removeTabViewItem:[tabView selectedTabViewItem]];
	} 
	else {
		[[self window] performClose:self];
	}
}

/**
 * Select next tab; if last select first one.
 */
- (IBAction) selectNextDocumentTab:(id)sender
{
	if([tabView indexOfTabViewItem:[tabView selectedTabViewItem]] == [tabView numberOfTabViewItems] - 1)
		[tabView selectFirstTabViewItem:nil];
	else
		[tabView selectNextTabViewItem:nil];
}

/**
 * Select previous tab; if first select last one.
 */
- (IBAction) selectPreviousDocumentTab:(id)sender
{
	if([tabView indexOfTabViewItem:[tabView selectedTabViewItem]] == 0)
		[tabView selectLastTabViewItem:nil];
	else
		[tabView selectPreviousTabViewItem:nil];
}

/**
 * Move the currently selected tab to a new window.
 */
- (IBAction)moveSelectedTabInNewWindow:(id)sender
{
	static NSPoint cascadeLocation = {.x = 0, .y = 0};

	SPDatabaseDocument *selectedDocument = [[tabView selectedTabViewItem] identifier];
	NSTabViewItem *selectedTabViewItem = [tabView selectedTabViewItem];
	PSMTabBarCell *selectedCell = [[tabBar cells] objectAtIndex:[tabView indexOfTabViewItem:selectedTabViewItem]];

	SPWindowController *newWindowController = [[SPWindowController alloc] initWithWindowNibName:@"MainWindow"];
	NSWindow *newWindow = [newWindowController window];

	CGFloat toolbarHeight = 0;
	
	if ([[[self window] toolbar] isVisible]) {
		NSRect innerFrame = [NSWindow contentRectForFrameRect:[[self window] frame] styleMask:[[self window] styleMask]];
		toolbarHeight = innerFrame.size.height - [[[self window] contentView] frame].size.height;
	}
	
	// Set the new window position and size
	NSRect targetWindowFrame = [[self window] frame];
	targetWindowFrame.size.height -= toolbarHeight;
	[newWindow setFrame:targetWindowFrame display:NO];

	// Cascade according to the statically stored cascade location.
	cascadeLocation = [newWindow cascadeTopLeftFromPoint:cascadeLocation];

	// Set the window controller as the window's delegate
	[newWindow setDelegate:newWindowController];

	// Set window title
	[newWindow setTitle:[[[[tabView selectedTabViewItem] identifier] parentWindow] title]];

	// New window's tabBar control
	PSMTabBarControl *control = [newWindowController valueForKey:@"tabBar"];

	// Add the selected tab to the new window
	[[control cells] insertObject:selectedCell atIndex:0];

	// Remove 'isProcessing' observer from old windowController
	[selectedDocument removeObserver:self forKeyPath:@"isProcessing"];

	// Update new 'isProcessing' observer and bind the new tab bar's progress display to the document
	[self _updateProgressIndicatorForItem:selectedTabViewItem];

	//remove the tracking rects and bindings registered on the old tab
	[tabBar removeTrackingRect:[selectedCell closeButtonTrackingTag]];
	[tabBar removeTrackingRect:[selectedCell cellTrackingTag]];
	[tabBar removeTabForCell:selectedCell];

	//rebind the selected cell to the new control
	[control bindPropertiesForCell:selectedCell andTabViewItem:selectedTabViewItem];
	
	[selectedCell setControlView:control];
	
	[[tabBar tabView] removeTabViewItem:[selectedCell representedObject]];

	[[control tabView] addTabViewItem:selectedTabViewItem];

	// Make sure the new tab is set in the correct position by forcing an update
	[tabBar update:NO];

	// Update tabBar of the new window
	[newWindowController tabView:[tabBar tabView] didDropTabViewItem:[selectedCell representedObject] inTabBar:control];

	[newWindow makeKeyAndOrderFront:nil];	
}

/**
 * Toggle Tab Bar Visibility
 */

- (IBAction)toggleTabBarShown:(id)sender
{
	[tabBar setHideForSingleTab:![tabBar hideForSingleTab]];
	[[NSUserDefaults standardUserDefaults] setBool:![tabBar hideForSingleTab] forKey:SPAlwaysShowWindowTabBar];
}

/**
 * Menu validation
 */
- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{

	// Select Next/Previous/Move Tab
	if (   [menuItem action] == @selector(selectPreviousDocumentTab:) 
		|| [menuItem action] == @selector(selectNextDocumentTab:)
		|| [menuItem action] == @selector(moveSelectedTabInNewWindow:))
	{
		return ([tabView numberOfTabViewItems] != 1);
	}

	// Show/hide Tab bar
	if ([menuItem action] == @selector(toggleTabBarShown:)) {
		[menuItem setTitle:(![tabBar isTabBarHidden] ? NSLocalizedString(@"Hide Tab Bar", @"hide tab bar") : NSLocalizedString(@"Show Tab Bar", @"show tab bar"))];
		return [[tabBar cells] count] <= 1;
	}
	
	// See if the front document blocks validation of this item
	if (![selectedTableDocument validateMenuItem:menuItem]) return NO;

	return YES;
}

/**
 * Retrieve the documents associated with this window.
 */
- (NSArray *)documents
{
	NSMutableArray *documentsArray = [NSMutableArray array];
	for (NSTabViewItem *eachItem in [tabView tabViewItems]) {
		[documentsArray addObject:[eachItem identifier]];
	}
	return documentsArray;
}

/**
 * Select tab at index.
 */
- (void)selectTabAtIndex:(NSInteger)index
{
	if([[tabBar cells] count] > 0 && [[tabBar cells] count] > (NSUInteger)index) {
		[tabView selectTabViewItemAtIndex:index];
	} else if([[tabBar cells] count]) {
		[tabView selectTabViewItemAtIndex:0];
	}

}

- (void)setHideForSingleTab:(BOOL)hide
{
	[tabBar setHideForSingleTab:hide];
}

/**
 * Opens the current connection in a new tab, but only if it's already connected.
 */
- (void)openDatabaseInNewTab
{
	if ([selectedTableDocument database]) {
		[selectedTableDocument openDatabaseInNewTab:self];
	}
}

#pragma mark -
#pragma mark First responder forwarding to active tab

/**
 * Delegate unrecognised methods to the selected table document, thanks to the magic
 * of NSInvocation (see forwardInvocation: docs for background). Must be paired
 * with methodSignationForSelector:.
 */
- (void) forwardInvocation:(NSInvocation *)theInvocation
{
	SEL theSelector = [theInvocation selector];
	if (![selectedTableDocument respondsToSelector:theSelector]) [self doesNotRecognizeSelector:theSelector];
	[theInvocation invokeWithTarget:selectedTableDocument];
}

/**
 * Return the correct method signatures for the selected table document if
 * NSObject doesn't implement the requested methods.
 */
- (NSMethodSignature *) methodSignatureForSelector:(SEL)theSelector
{
	NSMethodSignature *defaultSignature = [super methodSignatureForSelector:theSelector];
	if (defaultSignature) return defaultSignature;

	return [selectedTableDocument methodSignatureForSelector:theSelector];
}

/**
 * Override the default repondsToSelector:, returning true if either NSObject
 * or the selected table document supports the selector.
 */
- (BOOL) respondsToSelector:(SEL)theSelector
{
	return ([super respondsToSelector:theSelector] || (selectedTableDocument && [selectedTableDocument respondsToSelector:theSelector]));
}

/**
 * Override the default performSelector:, again either using NSObject defaults
 * or performing the selector on the selected table document.
 */
- (id) performSelector:(SEL)theSelector
{
	if ([super respondsToSelector:theSelector]) return [super performSelector:theSelector];

	if (![selectedTableDocument respondsToSelector:theSelector]) [self doesNotRecognizeSelector:theSelector];
	return [selectedTableDocument performSelector:theSelector];
}

/**
 * Override the default performSelector:withObject: - see performSelector:
 */
- (id) performSelector:(SEL)theSelector withObject:(id)theObject
{
	if ([super respondsToSelector:theSelector]) return [super performSelector:theSelector withObject:theObject];

	if (![selectedTableDocument respondsToSelector:theSelector]) [self doesNotRecognizeSelector:theSelector];
	return [selectedTableDocument performSelector:theSelector withObject:theObject];
}

/**
 * When receiving an update for a bound value - an observed value on the
 * document - ask the tab bar control to redraw as appropriate.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    [tabBar update];
}

/**
 * Binds a tab bar item's progress indicator to the represented
 * tableDocument.
 */
- (void)_updateProgressIndicatorForItem:(NSTabViewItem *)theItem
{
	PSMTabBarCell *theCell = [[tabBar cells] objectAtIndex:[tabView indexOfTabViewItem:theItem]];
	[[theCell indicator] setControlSize:NSSmallControlSize];
	SPDatabaseDocument *theDocument = [theItem identifier];
	
	[[theCell indicator] setHidden:NO];
	NSMutableDictionary *bindingOptions = [NSMutableDictionary dictionary];
	[bindingOptions setObject:NSNegateBooleanTransformerName forKey:@"NSValueTransformerName"];
	[[theCell indicator] bind:@"animate" toObject:theDocument withKeyPath:@"isProcessing" options:nil];
	[[theCell indicator] bind:@"hidden" toObject:theDocument withKeyPath:@"isProcessing" options:bindingOptions];
	[theDocument addObserver:self forKeyPath:@"isProcessing" options:0 context:nil];
}

@end