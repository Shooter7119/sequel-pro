//
//  $Id$
//
//  SPXMLExporter.h
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on October 6, 2009
//  Copyright (c) 2009 Stuart Connolly. All rights reserved.
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

#import "SPXMLExporter.h"
#import "SPExportFile.h"
#import "SPFileHandle.h"
#import "SPExportUtilities.h"
#import "SPMySQL.h"

@implementation SPXMLExporter

@synthesize delegate;
@synthesize xmlDataArray;
@synthesize xmlTableName;
@synthesize xmlNULLString;
@synthesize xmlOutputIncludeStructure;
@synthesize xmlOutputIncludeContent;
@synthesize xmlFormat;

/**
 * Initialise an instance of SPXMLExporter using the supplied delegate.
 *
 * @param exportDelegate The exporter delegate
 *
 * @return The initialised instance
 */
- (id)initWithDelegate:(NSObject *)exportDelegate
{
	if ((self = [super init])) {
		SPExportDelegateConformsToProtocol(exportDelegate, @protocol(SPXMLExporterProtocol));
		
		[self setDelegate:exportDelegate];
	}
	
	return self;
}

/**
 * Start the XML export process. This method is automatically called when an instance of this class
 * is placed on an NSOperationQueue. Do not call it directly as there is no manual multithreading.
 */
- (void)main
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	BOOL isTableExport = NO;
	
	NSArray *xmlRow = nil;
	NSArray *fieldNames = nil;
	NSString *dataConversionString = nil;
	
	// Result sets
	SPMySQLResult *statusResult = nil;
	SPMySQLResult *structureResult = nil;
	SPMySQLFastStreamingResult *streamingResult = nil;
	
	NSMutableArray *xmlTags    = [NSMutableArray array];
	NSMutableString *xmlString = [NSMutableString string];
	NSMutableString *xmlItem   = [NSMutableString string];
	
	NSUInteger xmlRowCount = 0;
	NSUInteger i, totalRows, currentRowIndex, lastProgressValue, currentPoolDataLength;
	
	// Check to see if we have at least a table name or data array
	if ((![self xmlTableName]) && (![self xmlDataArray]) ||
		([[self xmlTableName] length] == 0) && ([[self xmlDataArray] count] == 0) ||
		(([self xmlFormat] == SPXMLExportMySQLFormat) && ((![self xmlOutputIncludeStructure]) && (![self xmlOutputIncludeContent]))) ||
		(([self xmlFormat] == SPXMLExportPlainFormat) && (![self xmlNULLString])))
	{
		[pool release];
		return;
	}
			
	// Inform the delegate that the export process is about to begin
	[delegate performSelectorOnMainThread:@selector(xmlExportProcessWillBegin:) withObject:self waitUntilDone:NO];
	
	// Mark the process as running
	[self setExportProcessIsRunning:YES];
	
	lastProgressValue = 0;
	
	// Make a streaming request for the data if the data array isn't set
	if ((![self xmlDataArray]) && [self xmlTableName]) {
		
		isTableExport = YES;
		
		totalRows       = [[connection getFirstFieldFromQuery:[NSString stringWithFormat:@"SELECT COUNT(1) FROM %@", [[self xmlTableName] backtickQuotedString]]] integerValue];
		streamingResult = [connection streamingQueryString:[NSString stringWithFormat:@"SELECT * FROM %@", [[self xmlTableName] backtickQuotedString]] useLowMemoryBlockingStreaming:[self exportUsingLowMemoryBlockingStreaming]];
	
		// Only include the structure if necessary
		if (([self xmlFormat] == SPXMLExportMySQLFormat) && [self xmlOutputIncludeStructure]) {
		
			structureResult = [connection queryString:[NSString stringWithFormat:@"SHOW COLUMNS FROM %@", [[self xmlTableName] backtickQuotedString]]];
			NSMutableString *escapedTableName = [NSMutableString stringWithString:[[self xmlTableName] tickQuotedString]];
			[escapedTableName replaceOccurrencesOfString:@"\\" withString:@"\\\\\\\\" options:0 range:NSMakeRange(0, [escapedTableName length])];
			statusResult    = [connection queryString:[NSString stringWithFormat:@"SHOW TABLE STATUS LIKE %@", escapedTableName]];
			
			if ([structureResult numberOfRows] && [statusResult numberOfRows]) {

				[xmlString appendFormat:@"\t<table_structure name=\"%@\">\n", [self xmlTableName]];
				
				for (NSDictionary *row in structureResult)
				{
					[xmlString appendFormat:@"\t\t<field field=\"%@\" type=\"%@\" null=\"%@\" key=\"%@\" default=\"%@\" extra=\"%@\" />\n",
					 [row objectForKey:@"Field"],
					 [row objectForKey:@"Type"],
					 [row objectForKey:@"Null"],
					 [row objectForKey:@"Key"],
					 [row objectForKey:@"Default"],
					 [row objectForKey:@"Extra"]];				
				}
				
				NSDictionary *row = [statusResult getRowAsDictionary];
				
				[xmlString appendFormat:@"\n\t\t<options name=\"%@\" engine=\"%@\" version=\"%@\" row_format=\"%@\" rows=\"%@\" avg_row_length=\"%@\" data_length=\"%@\" max_data_length=\"%@\" index_length=\"%@\" data_free=\"%@\" create_time=\"%@\" update_time=\"%@\" collation=\"%@\" create_options=\"%@\" comment=\"%@\" />\n",
				 [row objectForKey:@"Name"],
				 [row objectForKey:@"Engine"],
				 [row objectForKey:@"Version"],
				 [row objectForKey:@"Row_format"],
				 [row objectForKey:@"Rows"],
				 [row objectForKey:@"Avg_row_length"],
				 [row objectForKey:@"Data_length"],
				 [row objectForKey:@"Max_data_length"],
				 [row objectForKey:@"Index_length"],
				 [row objectForKey:@"Data_free"],
				 [row objectForKey:@"Create_time"],
				 [row objectForKey:@"Update_time"],
				 [row objectForKey:@"Collation"],
				 [row objectForKey:@"Create_options"],
				 [row objectForKey:@"Comment"]];
				
				[xmlString appendFormat:@"\t</table_structure>\n\n"];
			}
		}
		
		if (([self xmlFormat] == SPXMLExportMySQLFormat) && [self xmlOutputIncludeContent]) {
			[xmlString appendFormat:@"\t<table_data name=\"%@\">\n\n", [self xmlTableName]];
		}
		
		[[self exportOutputFile] writeData:[xmlString dataUsingEncoding:[self exportOutputEncoding]]];
	}
	else {
		totalRows = [[self xmlDataArray] count];
	}
	
	// Only proceed to export the content if this is not a table export or it is and include content is selected
	if ((!isTableExport) || (isTableExport && [self xmlOutputIncludeContent])) {
	
		// Set up an array of encoded field names as opening and closing tags
		fieldNames = ([self xmlDataArray]) ? NSArrayObjectAtIndex([self xmlDataArray], 0) : [streamingResult fieldNames];
		
		for (i = 0; i < [fieldNames count]; i++) 
		{
			[xmlTags addObject:[NSMutableArray array]];
			
			[NSArrayObjectAtIndex(xmlTags, i) addObject:[NSString stringWithFormat:@"\t\t<%@>", [[NSArrayObjectAtIndex(fieldNames, i) description] HTMLEscapeString]]];
			[NSArrayObjectAtIndex(xmlTags, i) addObject:[NSString stringWithFormat:@"</%@>\n", [[NSArrayObjectAtIndex(fieldNames, i) description] HTMLEscapeString]]];
		}
		
		// If required, write an opening tag in the form of the table name
		if ([self xmlFormat] == SPXMLExportPlainFormat) {
			[[self exportOutputFile] writeData:[[NSString stringWithFormat:@"\t<%@>\n", ([self xmlTableName]) ? [[self xmlTableName] HTMLEscapeString] : @"custom"] dataUsingEncoding:[self exportOutputEncoding]]];
		}
		
		// Set up the starting row, which is 0 for streaming result sets and
		// 1 for supplied arrays which include the column headers as the first row.
		currentRowIndex = 0;
		
		if ([self xmlDataArray]) currentRowIndex++;
		
		// Drop into the processing loop
		NSAutoreleasePool *xmlExportPool = [[NSAutoreleasePool alloc] init];
		
		currentPoolDataLength = 0;
		
		// Inform the delegate that we are about to start writing the data to disk
		[delegate performSelectorOnMainThread:@selector(xmlExportProcessWillBeginWritingData:) withObject:self waitUntilDone:NO];
		
		while (1) 
		{
			// Check for cancellation flag
			if ([self isCancelled]) {
				if (streamingResult) {
					[connection cancelCurrentQuery];
					[streamingResult cancelResultLoad];
				}
				
				[xmlExportPool release];
				[pool release];
				
				return;
			}
			
			// Retrieve the next row from the supplied data, either directly from the array...
			if ([self xmlDataArray]) {
				xmlRow = NSArrayObjectAtIndex([self xmlDataArray], currentRowIndex);
			} 
			// Or by reading an appropriate row from the streaming result
			else {
				xmlRow = [streamingResult getRowAsArray];
				
				if (!xmlRow) break;
			}
			
			// Get the cell count if we don't already have it stored
			if (!xmlRowCount) xmlRowCount = [xmlRow count];
			
			// Construct the row
			[xmlString setString:@"\t<row>\n"];
			
			for (i = 0; i < xmlRowCount; i++) 
			{
				// Check for cancellation flag
				if ([self isCancelled]) {
					if (streamingResult) {
						[connection cancelCurrentQuery];
						[streamingResult cancelResultLoad];
					}
					
					[xmlExportPool release];
					[pool release];
					
					return;
				}
				
				BOOL dataIsNULL = NO;
				id data = NSArrayObjectAtIndex(xmlRow, i);
				
				// Retrieve the contents of this tag
				if ([data isKindOfClass:[NSData class]]) {
					dataConversionString = [[NSString alloc] initWithData:data encoding:[self exportOutputEncoding]];
					
					if (dataConversionString == nil) {
						dataConversionString = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
					}
					
					[xmlItem setString:[NSString stringWithString:dataConversionString]];
					[dataConversionString release];
				} 
				else if (data == [NSNull null]) {
					dataIsNULL = YES;
					
					if ([self xmlFormat] == SPXMLExportPlainFormat) {
						[xmlItem setString:[self xmlNULLString]];
					}
				}
				else if ([data isKindOfClass:[SPMySQLGeometryData class]]) {
					[xmlItem setString:[data wktString]];
				}
				else {
					[xmlItem setString:[data description]];
				}
				
				if ([self xmlFormat] == SPXMLExportMySQLFormat) {
					[xmlString appendFormat:@"\t\t<field name=\"%@\"", [[NSArrayObjectAtIndex(fieldNames, i) description] HTMLEscapeString]];
					
					if (dataIsNULL) {
						[xmlString appendString:@" xsi:nil=\"true\" \\>\n"];
					}
					else {
						[xmlString appendFormat:@">%@</field>\n", [xmlItem HTMLEscapeString]];
					}
				}
				else if ([self xmlFormat] == SPXMLExportPlainFormat) {
					// Add the opening and closing tag and the contents to the XML string
					[xmlString appendString:NSArrayObjectAtIndex(NSArrayObjectAtIndex(xmlTags, i), 0)];
					[xmlString appendString:[xmlItem HTMLEscapeString]];
					[xmlString appendString:NSArrayObjectAtIndex(NSArrayObjectAtIndex(xmlTags, i), 1)];
				}
			}
			
			[xmlString appendString:@"\t</row>\n\n"];
			
			// Record the total length for use with pool flushing
			currentPoolDataLength += [xmlString length];
			
			// Write the row to the filehandle
			[[self exportOutputFile] writeData:[xmlString dataUsingEncoding:[self exportOutputEncoding]]];
			
			// Update the progress counter and progress bar
			currentRowIndex++;
			
			// Update the progress
			if (totalRows && (currentRowIndex * ([self exportMaxProgress] / totalRows)) > lastProgressValue) {
				
				NSInteger progress = (currentRowIndex * ([self exportMaxProgress] / totalRows));
				
				[self setExportProgressValue:progress];
				
				lastProgressValue = progress;
			}
			
			// Inform the delegate that the export's progress has been updated
			[delegate performSelectorOnMainThread:@selector(xmlExportProcessProgressUpdated:) withObject:self waitUntilDone:NO];
			
			// Drain the autorelease pool as required to keep memory usage low
			if (currentPoolDataLength > 250000) {
				[xmlExportPool release];
				xmlExportPool = [[NSAutoreleasePool alloc] init];
			}
			
			// If an array was supplied and we've processed all rows, break
			if ([self xmlDataArray] && totalRows == currentRowIndex) break;
		}
		
		if (([self xmlFormat] == SPXMLExportMySQLFormat) && isTableExport) {
			[[self exportOutputFile] writeData:[@"\t</table_data>\n\n" dataUsingEncoding:[self exportOutputEncoding]]];
		}
		else if ([self xmlFormat] == SPXMLExportPlainFormat) {
			[[self exportOutputFile] writeData:[[NSString stringWithFormat:@"\t</%@>\n\n", ([self xmlTableName]) ? [[self xmlTableName] HTMLEscapeString] : @"custom"] dataUsingEncoding:[self exportOutputEncoding]]];
		}
		
		[xmlExportPool release];
	}
	
	// Write data to disk
	[[[self exportOutputFile] exportFileHandle] synchronizeFile];
	
	// Mark the process as not running
	[self setExportProcessIsRunning:NO];
	
	// Inform the delegate that the export process is complete
	[delegate performSelectorOnMainThread:@selector(xmlExportProcessComplete:) withObject:self waitUntilDone:NO];
	
	[pool release];
}

/**
 * Dealloc
 */
- (void)dealloc
{
	if (xmlDataArray) [xmlDataArray release], xmlDataArray = nil;
	if (xmlTableName) [xmlTableName release], xmlTableName = nil;
	if (xmlNULLString) [xmlNULLString release], xmlNULLString = nil;
	
	[super dealloc];
}

@end