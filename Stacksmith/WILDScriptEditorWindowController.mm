//
//  WILDScriptEditorWindowController.m
//  Propaganda
//
//  Created by Uli Kusterer on 13.03.10.
//  Copyright 2010 The Void Software. All rights reserved.
//

#import "WILDScriptEditorWindowController.h"
#import "UKSyntaxColoredTextViewController.h"
#import "NSWindow+ULIZoomEffect.h"
#include "Forge.h"
#include "CMacPartBase.h"
#include "CStackMac.h"
#include "CDocument.h"
#import "UKHelperMacros.h"


using namespace Carlson;


static NSString	*	WILDScriptEditorTopAreaToolbarItemIdentifier = @"WILDScriptEditorTopAreaToolbarItemIdentifier";



@protocol WILDScriptEditorHandlerListDelegate <NSObject>

-(void)	scriptEditorAddHandlersPopupDidSelectHandler: (NSDictionary*)inDictionary;

@end


@interface WILDScriptEditorRulerView : NSRulerView
{
	NSTextView			*	targetView;
	NSMutableIndexSet	*	selectedLines;
}

@property (copy,nonatomic) NSIndexSet	*	selectedLines;

@end

@implementation WILDScriptEditorRulerView

-(id)	initWithTargetView: (NSTextView*)inTargetView
{
	self = [super initWithFrame: NSMakeRect(0, 0, 8, 8)];
	if( self )
	{
		targetView = inTargetView;
		selectedLines = [[NSMutableIndexSet alloc] init];
	}
	return self;
}


-(void)	dealloc
{
	DESTROY_DEALLOC(selectedLines);
	targetView = nil;
	
	[super dealloc];
}


-(NSIndexSet*)	selectedLines
{
	return selectedLines;
}


-(void)	setSelectedLines: (NSIndexSet*)inSelectedLines
{
	DESTROY(selectedLines);
	selectedLines = [inSelectedLines mutableCopy];
	[self setNeedsDisplay: YES];
}


-(CGFloat)	ruleThickness
{
	return 16;
}


-(CGFloat)	requiredThickness
{
	return 16;
}


-(void)	drawRect: (NSRect)inFrame
{
	[NSColor.whiteColor set];
	[NSBezierPath fillRect: self.bounds];
	NSRect			theBox = [self bounds];
	NSString	*	string = targetView.string;
	
	NSUInteger	currIndex = [selectedLines indexGreaterThanOrEqualToIndex: 0];
	while(( currIndex != NSNotFound ))
	{
		NSUInteger numberOfLines = 1, index = 0;

		for( ; numberOfLines < currIndex; numberOfLines++ )
			index = NSMaxRange([string lineRangeForRange:NSMakeRange(index, 0)]);
		
		NSUInteger	theGlyphIdx = [targetView.layoutManager glyphIndexForCharacterAtIndex: index];
		NSRange		effectiveRange = { 0, 0 };
		NSRect		lineFragmentBox = [targetView.layoutManager lineFragmentRectForGlyphAtIndex:theGlyphIdx effectiveRange: &effectiveRange];
		NSRect		checkpointBox = { NSZeroPoint, { 8, 8 } };
		
		checkpointBox.origin.y = lineFragmentBox.origin.y + truncf((lineFragmentBox.size.height -checkpointBox.size.height) /2) -self.scrollView.documentVisibleRect.origin.y;
		checkpointBox.origin.x = truncf((theBox.size.width -checkpointBox.size.width) /2);
		
		[NSColor.redColor set];
		[[NSBezierPath bezierPathWithOvalInRect: checkpointBox] fill];
		
		currIndex = [selectedLines indexGreaterThanIndex: currIndex];
	}
}


-(void)	mouseDown: (NSEvent*)inEvent
{
	NSPoint		pos = [self convertPoint: inEvent.locationInWindow fromView: nil];
	CGFloat		insertionMarkFraction = 0;
	pos.x = 4;
	NSUInteger	charIndex = [targetView.layoutManager characterIndexForPoint: pos inTextContainer:targetView.textContainer fractionOfDistanceBetweenInsertionPoints: &insertionMarkFraction];
	
	NSString *string = targetView.string;
	NSUInteger numberOfLines = 0, index = 0;

	for( ; index <= charIndex; numberOfLines++ )
		index = NSMaxRange([string lineRangeForRange:NSMakeRange(index, 0)]);
	
	if( [selectedLines containsIndex: numberOfLines] )
		[selectedLines removeIndex: numberOfLines];
	else
		[selectedLines addIndex: numberOfLines];
	[self setNeedsDisplay: YES];
}

@end


@interface WILDScriptEditorHandlerListPopoverViewController : NSViewController <NSTableViewDataSource>
{
	NSArray*		mHandlerList;
}

@property (nonatomic,assign) IBOutlet NSTableView*		handlersTable;
@property (nonatomic,assign) id<WILDScriptEditorHandlerListDelegate>	delegate;

@end


@implementation WILDScriptEditorHandlerListPopoverViewController

-(id)	initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
	self = [super initWithNibName: nibNameOrNil bundle: nibBundleOrNil];
	if( self )
	{
		ASSIGN(mHandlerList,[NSArray arrayWithContentsOfFile: [[NSBundle bundleForClass: [self class]] pathForResource: @"WILDAddHandlersList" ofType: @"plist"]]);
	}
	return self;
}


-(void)	dealloc
{
	DESTROY_DEALLOC(mHandlerList);
	[super dealloc];
}


-(NSInteger)	numberOfRowsInTableView: (NSTableView *)tableView
{
	return mHandlerList.count;
}


-(id)	tableView: (NSTableView *)tableView objectValueForTableColumn: (NSTableColumn *)tableColumn row: (NSInteger)row
{
	NSString*	 desc = [[mHandlerList objectAtIndex: row] objectForKey: @"WILDHandlerDescription"];
	if( desc )
	{
		NSMutableAttributedString	*	attrStr = [[[NSMutableAttributedString alloc] initWithString:[[mHandlerList objectAtIndex: row] objectForKey: @"WILDHandlerName"] attributes: @{ NSFontAttributeName: [NSFont boldSystemFontOfSize: [NSFont smallSystemFontSize]] }] autorelease];
		NSMutableAttributedString	*	greyDesc = [[[NSMutableAttributedString alloc] initWithString: [@" • " stringByAppendingString: desc] attributes: @{ NSFontAttributeName: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]], NSForegroundColorAttributeName: [NSColor grayColor] }] autorelease];
		
		[attrStr appendAttributedString: greyDesc];
		
		return attrStr;
	}
	else
	{
		return [[mHandlerList objectAtIndex: row] objectForKey: @"WILDHandlerName"];
	}
}


-(BOOL)	tableView: (NSTableView *)tableView isGroupRow: (NSInteger)row
{
	return [[[mHandlerList objectAtIndex: row] objectForKey: @"WILDHandlerGroupRow"] boolValue];
}


-(void)	tableViewSelectionDidChange: (NSNotification*)notif
{
	if( self.handlersTable.selectedRow == -1 )
		return;	// Nothing selected, nothing to do.
	NSDictionary	*	selectedDict = [mHandlerList objectAtIndex: self.handlersTable.selectedRow];
	if( [selectedDict[@"WILDHandlerGroupRow"] boolValue] )	// Don't let the user insert handlers named after headlines.
		return;
	
	[self.delegate scriptEditorAddHandlersPopupDidSelectHandler: selectedDict];
}

@end


@interface WILDScriptEditorWindowController () <NSToolbarDelegate,NSPopoverDelegate,WILDScriptEditorHandlerListDelegate>

@end


@implementation WILDScriptEditorWindowController

-(id)	initWithScriptContainer: (CConcreteObject*)inContainer
{
	if(( self = [super initWithWindowNibName: NSStringFromClass( [self class] )] ))
	{
		mContainer = inContainer;
	}
	
	return self;
}


-(void)	dealloc
{
	mContainer = NULL;
	
	[super dealloc];
}


-(void)	awakeFromNib
{
	[super awakeFromNib];
	
	WILDScriptEditorRulerView	*	theRulerView = [[[WILDScriptEditorRulerView alloc] initWithTargetView: mTextView] autorelease];
	[mTextScrollView setHasVerticalRuler: YES];
	[mTextScrollView setVerticalRulerView: theRulerView];
	[mTextScrollView setRulersVisible: YES];
	
	[self formatText];
	
	NSToolbar	*	editToolbar = [[[NSToolbar alloc] initWithIdentifier: @"WILDScriptEditorToolbar"] autorelease];
	[editToolbar setDelegate: self];
	[editToolbar setAllowsUserCustomization: NO];
	[editToolbar setVisible: NO];
	[editToolbar setDisplayMode: NSToolbarDisplayModeIconOnly];
	[editToolbar setSizeMode: NSToolbarSizeModeSmall];
	[self.window setToolbar: editToolbar];
	[self.window toggleToolbarShown: self];

	mTextView.automaticQuoteSubstitutionEnabled = NO;
	mTextView.automaticDashSubstitutionEnabled = NO;
	mTextView.automaticTextReplacementEnabled = NO;
}


-(void)	formatText
{
	char*			theText = NULL;
	size_t			theTextLen = 0;
	NSRange			selRange = mTextView.selectedRange;
	size_t			cursorPos = selRange.location,
					cursorEndPos = selRange.location +selRange.length;
	size_t			theLine = 0;
	size_t			errOffset = 0;
	size_t			x = 0;
	const char*		currErrMsg = "";
	LEOParseTree*	parseTree = LEOParseTreeCreateFromUTF8Characters( mContainer->GetScript().c_str(), mContainer->GetScript().length(), 0 );
	for( x = 0; currErrMsg != NULL; x++ )
	{
		LEOParserGetNonFatalErrorMessageAtIndex( x, &currErrMsg, &theLine, &errOffset );
		if( !currErrMsg )
			break;
		fprintf( stderr, "Error: %s\n", currErrMsg );
	}
	LEODisplayInfoTable*	displayInfo = LEODisplayInfoTableCreateForParseTree( parseTree );
	LEODisplayInfoTableApplyToText( displayInfo, mContainer->GetScript().c_str(), mContainer->GetScript().length(), &theText, &theTextLen, &cursorPos, &cursorEndPos );
	NSString	*	formattedText = [[[NSString alloc] initWithBytesNoCopy: theText length: theTextLen encoding: NSUTF8StringEncoding freeWhenDone: YES] autorelease];
	[mTextView setString: formattedText];
	[mTextView setSelectedRange: NSMakeRange(cursorPos,cursorEndPos -cursorPos)];
	
	[mPopUpButton removeAllItems];
	const char*	theName = "";
	
	bool		isCommand = false;
	for( x = 0; theName != NULL; x++ )
	{
		LEODisplayInfoTableGetHandlerInfoAtIndex( displayInfo, x, &theName, &theLine, &isCommand );
		if( !theName ) break;
		if( theName[0] == ':' )	// Skip any fake internal handlers we add.
			continue;
		NSMenuItem*	theItem = [mPopUpButton.menu addItemWithTitle: [NSString stringWithUTF8String: theName] action: Nil keyEquivalent: @""];
		[theItem setImage: [NSImage imageNamed: isCommand ? @"HandlerPopupMessage" : @"HandlerPopupFunction"]];
		[theItem setRepresentedObject: @(theLine)];
	}
	LEOCleanUpDisplayInfoTable( displayInfo );
	LEOCleanUpParseTree( parseTree );
	
	if( x == 0 )	// We added no items?
	{
		[mPopUpButton addItemWithTitle: @"None"];
		[mPopUpButton setEnabled: NO];
	}
}


-(void)	showWindow:(id)sender
{
	NSWindow	*	theWindow = [self window];
	NSURL		*	theURL = [NSURL URLWithString: [NSString stringWithUTF8String: mContainer->GetDocument()->GetURL().c_str()]];
	[theWindow setTitleWithRepresentedFilename: theURL.path];

	NSButton				*	btn = [[self window] standardWindowButton: NSWindowDocumentIconButton];
	CMacScriptableObjectBase*	macPart = dynamic_cast<CMacScriptableObjectBase*>(mContainer);
	if( macPart )
		[btn setImage: macPart->GetDisplayIcon()];
	[theWindow setTitle: [self windowTitleForDocumentDisplayName: nil]];
	
	[theWindow makeKeyAndOrderFrontWithZoomEffectFromRect: mGlobalStartRect];
}


-(BOOL)	windowShouldClose: (id)sender
{
	NSWindow	*	theWindow = [self window];
	
	[theWindow orderOutWithZoomEffectToRect: mGlobalStartRect];
	
	return YES;
}


-(void)	windowWillClose: (NSNotification*)notification
{
	mContainer->SetScript( std::string(mTextView.string.UTF8String, [mTextView.string lengthOfBytesUsingEncoding: NSUTF8StringEncoding]) );
}


-(void) setDocument: (NSDocument *)document
{
	[super setDocument: document];
	
	NSButton*					btn = [[self window] standardWindowButton: NSWindowDocumentIconButton];
	CMacScriptableObjectBase*	macPart = dynamic_cast<CMacScriptableObjectBase*>(mContainer);
	if( macPart )
		[btn setImage: macPart->GetDisplayIcon()];
}


-(IBAction)	handlerPopupSelectionChanged: (id)sender
{
	NSNumber*	destLineObj = [mPopUpButton.selectedItem representedObject];
	[mSyntaxController goToLine: [destLineObj integerValue]];
}


-(IBAction)	addHandler: (id)sender
{
	if( mAddHandlersPopover )
	{
		[mAddHandlersPopover close];
	}
	else
	{
		mAddHandlersPopover = [[NSPopover alloc] init];
		WILDScriptEditorHandlerListPopoverViewController	*	vc = [[[WILDScriptEditorHandlerListPopoverViewController alloc] initWithNibName: @"WILDScriptEditorHandlerListPopover" bundle: [NSBundle bundleForClass: [self class]]] autorelease];
		vc.delegate = self;
		mAddHandlersPopover.contentViewController = vc;
		mAddHandlersPopover.behavior = NSPopoverBehaviorTransient;
		mAddHandlersPopover.delegate = self;
		[mAddHandlersPopover showRelativeToRect: [sender bounds] ofView: sender preferredEdge: NSMaxYEdge];
	}
}


-(void)	popoverDidClose:(NSNotification *)notification
{
	DESTROY(mAddHandlersPopover);
}


-(void)	scriptEditorAddHandlersPopupDidSelectHandler: (NSDictionary*)inDictionary
{
	NSString*	handlerName = [inDictionary objectForKey: @"WILDHandlerName"];
	NSNumber*	destLineObj = [[mPopUpButton itemWithTitle: handlerName.lowercaseString] representedObject];
	if( destLineObj )
	{
		[mSyntaxController goToLine: [destLineObj integerValue]];
	}
	else
	{
		NSString	*	str = [inDictionary objectForKey: @"WILDHandlerTemplate"];
		if( !str )
			str = [NSString stringWithFormat: @"\n\non %1$@\n\t\nend %1$@", handlerName];
		NSMutableAttributedString	*	attrStr = [[NSMutableAttributedString alloc] initWithString: str attributes: mSyntaxController.defaultTextAttributes];
		[mTextView.textStorage appendAttributedString: attrStr];
		
		[self reformatText];
	}
	[mAddHandlersPopover close];
}


-(NSString *)	windowTitleForDocumentDisplayName: (NSString *)displayName
{
	return [NSString stringWithFormat: @"%1$@’s Script", [NSString stringWithUTF8String: mContainer->GetDisplayName().c_str()]];
}


-(BOOL)	window: (NSWindow *)window shouldPopUpDocumentPathMenu: (NSMenu *)menu
{
	// Make sure the former top item (pointing to the file) selects the main doc window:
	CStackMac*		macStack = dynamic_cast<CStackMac*>(mContainer->GetStack());
	NSMenuItem*		fileItem = [menu itemAtIndex: 0];
	[fileItem setTarget: macStack->GetMacWindow()];
	[fileItem setAction: @selector(makeKeyAndOrderFront:)];
	
	// Now add a new item above that for this window, the script:
	NSMenuItem*		newItem = [menu insertItemWithTitle: [NSString stringWithFormat: @"%1$@’s Script", [NSString stringWithUTF8String: mContainer->GetDisplayName().c_str()]]
											action: nil keyEquivalent: @"" atIndex: 0];
	CMacScriptableObjectBase*	macPart = dynamic_cast<CMacScriptableObjectBase*>(mContainer);
	if( macPart )
		[newItem setImage: macPart->GetDisplayIcon()];
	
	return YES;
}


-(void)		setGlobalStartRect: (NSRect)theBox
{
	mGlobalStartRect = theBox;
}


-(void)		goToLine: (NSUInteger)lineNum
{
	[mSyntaxController goToLine: lineNum];
}


-(void)		goToCharacter: (NSUInteger)charNum
{
	[mSyntaxController goToCharacter: charNum];
}


-(void)	reformatText
{
	mContainer->SetScript( std::string(mTextView.string.UTF8String, [mTextView.string lengthOfBytesUsingEncoding: NSUTF8StringEncoding]) );
	[self formatText];
}


-(BOOL) textView: (NSTextView *)textView doCommandBySelector: (SEL)commandSelector
{
	if( commandSelector == @selector(insertTab:) )
	{
		[self reformatText];
		return YES;
	}
//	else if( commandSelector == @selector(insertNewline:) )
//	{
//		[self performSelector: @selector(reformatText) withObject: nil afterDelay: 0.0];
//		return NO;
//	}
	else
		return NO;
}


- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem	*	theItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdentifier] autorelease];
	
	if( [itemIdentifier isEqualToString: WILDScriptEditorTopAreaToolbarItemIdentifier] )
	{
		[theItem setLabel: @"Top Area"];
		[theItem setView: mTopNavAreaView];
	}
	
	return theItem;
}

/* Returns the ordered list of items to be shown in the toolbar by default.   If during initialization, no overriding values are found in the user defaults, or if the user chooses to revert to the default items this set will be used. */
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
	return @[ WILDScriptEditorTopAreaToolbarItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier ];
}

/* Returns the list of all allowed items by identifier.  By default, the toolbar does not assume any items are allowed, even the separator.  So, every allowed item must be explicitly listed.  The set of allowed items is used to construct the customization palette.  The order of items does not necessarily guarantee the order of appearance in the palette.  At minimum, you should return the default item list.*/
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
	return @[ WILDScriptEditorTopAreaToolbarItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier ];
}

@end
