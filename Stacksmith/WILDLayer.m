//
//  WILDLayer.m
//  Propaganda
//
//  Created by Uli Kusterer on 28.02.10.
//  Copyright 2010 The Void Software. All rights reserved.
//

#import "WILDLayer.h"
#import "WILDPart.h"
#import "WILDPartContents.h"
#import "WILDXMLUtils.h"
#import "ULIMultiMap.h"
#import "WILDStack.h"
#import "WILDDocument.h"
#import "WILDNotifications.h"
#import "UKRandomInteger.h"
#import "Forge.h"
#import "UKHelperMacros.h"


@implementation WILDLayer

@synthesize name = mName;
@synthesize dontSearch = mDontSearch;
@synthesize cantDelete = mCantDelete;

-(id)	initForStack: (WILDStack*)theStack
{
	if(( self = [super init] ))
	{
		mStack = theStack;
		
		mID = [mStack uniqueIDForCardOrBackground];
		mName = [@"" retain];

		mShowPict = YES;
		mCantDelete = NO;
		mDontSearch = NO;
		
		mScript = [@"" retain];
		mButtonFamilies = [[ULIMultiMap alloc] init];

		mParts = [[NSMutableArray alloc] init];
		mAddColorParts = [[NSMutableArray alloc] init];
		mContents = [[NSMutableDictionary alloc] init];
		
		mPartIDSeed = 1;
		
		mIDForScripts = kLEOObjectIDINVALID;
	}
	
	return self;
}


-(id)	initWithXMLDocument: (NSXMLDocument*)theDoc forStack: (WILDStack*)theStack
{
	if(( self = [super init] ))
	{
		NSXMLElement*	elem = [theDoc rootElement];
		
		mID = WILDIntegerFromSubElementInElement( @"id", elem );
		mName = [WILDStringFromSubElementInElement( @"name", elem ) retain];
		
		mShowPict = WILDBoolFromSubElementInElement( @"showPict", elem, YES );
		mCantDelete = WILDBoolFromSubElementInElement( @"cantDelete", elem, NO );
		mDontSearch = WILDBoolFromSubElementInElement( @"dontSearch", elem, NO );
		
		mStack = theStack;
		mPictureName = [WILDStringFromSubElementInElement( @"bitmap", elem ) retain];
		
		mScript = [WILDStringFromSubElementInElement( @"script", elem ) retain];

		NSError *	err = nil;
		NSArray	*	userPropsNodes = [elem nodesForXPath: @"userProperties" error: &err];
		if( userPropsNodes.count > 0 )
		{
			NSString		*	lastKey = nil;
			NSString		*	lastValue = nil;
			NSXMLElement	*	userPropsNode = [userPropsNodes objectAtIndex: 0];
			for( NSXMLElement* currChild in userPropsNode.children )
			{
				if( [currChild.name isEqualToString: @"name"] )
					lastKey = currChild.stringValue;
				if( !lastValue && [currChild.name isEqualToString: @"value"] )
					lastValue = currChild.stringValue;
				if( lastKey && lastValue )
				{
					if( !mUserProperties )
						mUserProperties = [[NSMutableDictionary alloc] init];
					[mUserProperties setObject: lastValue forKey: lastKey];
					lastValue = lastKey = nil;
				}
				if( lastValue && !lastKey )
					lastValue = nil;
			}
		}

		mButtonFamilies = [[ULIMultiMap alloc] init];
		
		NSArray*		parts = [elem elementsForName: @"part"];
		mParts = [[NSMutableArray alloc] initWithCapacity: [parts count]];
		for( NSXMLElement* currPart in parts )
		{
			WILDPart*	newPart = [[[WILDPart alloc] initWithXMLElement: currPart forStack: theStack] autorelease];
			[newPart setPartLayer: [self partLayer]];
			[newPart setPartOwner: self];
			[mParts addObject: newPart];
			[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(partDidChange:) name:WILDPartDidChangeNotification object: newPart];
			if( [newPart family] > 0 )
				[mButtonFamilies addObject: newPart forKey: [NSNumber numberWithInteger: [newPart family]]];
		}
		
		mAddColorParts = [[NSMutableArray alloc] init];
		NSArray*		contents = [elem elementsForName: @"content"];
		mContents = [[NSMutableDictionary alloc] initWithCapacity: [contents count]];
		for( NSXMLElement* currContent in contents )
		{
			WILDPartContents*	newCont = [[[WILDPartContents alloc] initWithXMLElement: currContent forStack: theStack] autorelease];
			[self addContents: newCont];
		}
		
		[self loadAddColorObjects: elem];
		
		mPartIDSeed = 1;
		
		mIDForScripts = kLEOObjectIDINVALID;
	}
	
	return self;
}


-(void)	dealloc
{
	for( WILDPart* currPart in mParts )
	{
		[[NSNotificationCenter defaultCenter] removeObserver: self name: WILDPartDidChangeNotification object: currPart];
	}
	
	DESTROY_DEALLOC(mButtonFamilies);
	DESTROY_DEALLOC(mName);
	DESTROY_DEALLOC(mScript);
	DESTROY_DEALLOC(mPicture);
	DESTROY_DEALLOC(mPictureName);
	DESTROY_DEALLOC(mParts);
	DESTROY_DEALLOC(mAddColorParts);
	DESTROY_DEALLOC(mUserProperties);
	
	if( mScriptObject )
	{
		LEOScriptRelease( mScriptObject );
		mScriptObject = NULL;
	}
	
	mStack = UKInvalidPointer;
	
	[super dealloc];
}


-(WILDObjectID)	backgroundID
{
	return mID;
}


-(NSImage*)		picture
{
	if( mPicture )
		return mPicture;
	
	if( !mPictureName )
		return nil;
	
	NSImage*	img = [(WILDDocument*)[mStack document] imageNamed: mPictureName];
	ASSIGN(mPicture,img);
	
	return img;
}


-(void)	setPicture: (NSImage *)inImage
{
	ASSIGN(mPicture,inImage);
	[self updateChangeCount: NSChangeDone];
}


-(NSArray*)	parts
{
	return mParts;
}


-(NSArray*)	addColorParts
{
	return mAddColorParts;
}

-(WILDPartContents*)	contentsForPart: (WILDPart*)thePart
{
	return [self contentsForPart: thePart create: NO];
}


-(WILDPartContents*)	contentsForPart: (WILDPart*)thePart create: (BOOL)createIfNeeded
{
	NSString*	theKey = [NSString stringWithFormat: @"%@:%lld", [thePart partLayer], [thePart partID]];
	WILDPartContents*	contents = [mContents objectForKey: theKey];
	if( !contents && createIfNeeded )
	{
		contents = [[[WILDPartContents alloc] initWithWILDObjectID: thePart.partID layer: thePart.partLayer] autorelease];
		[mContents setObject: contents forKey: theKey];
	}
	return contents;
}


-(WILDPart*)	partWithID: (WILDObjectID)theID
{
	for( WILDPart* thePart in mParts )
	{
		if( [thePart partID] == theID )
			return thePart;
	}
	
	return nil;
}


-(NSString*)	partLayer
{
	return @"background";
}


-(BOOL)	showPicture
{
	return mShowPict;
}


-(void)	updatePartOnClick: (WILDPart*)thePart withCard: (WILDCard*)inCard background: (WILDBackground*)inBackground
{
	if( [thePart family] == 0 )
	{
		if( [thePart autoHighlight] && ([[thePart partStyle] isEqualToString: @"radiobutton"] || [[thePart partStyle] isEqualToString: @"checkbox"]) )
			[thePart setHighlighted: ![thePart highlighted]];
		return;
	}
	
	NSNumber*	theNum = [NSNumber numberWithInteger: [thePart family]];
	NSArray*	peers = [mButtonFamilies objectsForKey: theNum];
	
	for( WILDPart* currPart in peers )
	{
		WILDPartContents	*	contents = [currPart currentPartContentsAndBackgroundContents: nil create: YES onCard: inCard forBackgroundEditing: NO];
		BOOL					newState = (currPart == thePart);
		BOOL					isHighlighted = [currPart highlighted];
		if( ![currPart sharedHighlight] && [[currPart partLayer] isEqualToString: @"background"] )
			isHighlighted = [contents highlighted];
		if( [currPart highlighted] != newState
			|| currPart == thePart )	// Whack the clicked part over the head, in case NSButton turned something off we don't wanna, or if it's a non-toggling type of button we need to toggle manually.
		{
			if( [currPart.partLayer isEqualToString: @"background"] && ![currPart sharedHighlight] )
			{
				[contents setHighlighted: newState];
			}
			[currPart setHighlighted: newState];	// Must be after contents, as this triggers change notifications!
			//NSLog( @"Family: Setting highlight of %@ to %s", [currPart displayName], newState?"true":"false" );
		}
	}
}


-(void)	loadAddColorObjects: (NSXMLElement*)theElem
{
	NSArray*	theObjects = [theElem elementsForName: @"addcolorobject"];
	
	for( NSXMLElement* theObject in theObjects )
	{
		WILDObjectID	objectID = WILDIntegerFromSubElementInElement( @"id", theObject );
		NSInteger		objectBevel = WILDIntegerFromSubElementInElement( @"bevel", theObject );
		NSString*		objectType = WILDStringFromSubElementInElement( @"type", theObject );
		NSString*		objectName = WILDStringFromSubElementInElement( @"name", theObject );
		BOOL			objectTransparent = WILDBoolFromSubElementInElement( @"transparent", theObject, NO );
		BOOL			objectVisible = WILDBoolFromSubElementInElement( @"visible", theObject, YES );
		NSRect			objectRect = WILDRectFromSubElementInElement( @"rect", theObject );
		NSColor*		objectColor = WILDColorFromSubElementInElement( @"color", theObject );
		
		if( [objectType isEqualToString: @"button"] )
		{
			WILDPart*	thePart = [self partWithID: objectID];
			if( thePart )
			{
				[thePart setFillColor: objectColor];
				[thePart setBevel: objectBevel];
				[mAddColorParts addObject: thePart];
			}
		}
		else if( [objectType isEqualToString: @"field"] )
		{
			WILDPart*	thePart = [self partWithID: objectID];
			if( thePart )
			{
				[thePart setFillColor: objectColor];
				[thePart setBevel: objectBevel];
				[mAddColorParts addObject: thePart];
			}
		}
		else if( [objectType isEqualToString: @"rectangle"] )
		{
			WILDPart*	thePart = [[[WILDPart alloc] initWithXMLElement: nil forStack: mStack] autorelease];
			[thePart setFlippedRectangle: objectRect];
			[thePart setFillColor: objectColor];
			[thePart setBevel: objectBevel];
			[thePart setPartType: @"rectangle"];
			[thePart setPartStyle: @"opaque"];
			[thePart setVisible: objectVisible];
			[mAddColorParts addObject: thePart];
		}
		else if( [objectType isEqualToString: @"picture"] )
		{
			WILDPart*	thePart = [[[WILDPart alloc] initWithXMLElement: nil forStack: mStack] autorelease];
			[thePart setFlippedRectangle: objectRect];
			[thePart setName: objectName];
			[thePart setPartType: @"picture"];
			[thePart setPartStyle: objectTransparent ? @"transparent" : @"opaque"];
			[thePart setVisible: objectVisible];
			[mAddColorParts addObject: thePart];
		}
	}
}


-(NSURL*)	URLForPartTemplate: (NSString*)inName
{
	return [[NSBundle mainBundle] URLForResource: inName withExtension:@"xml" subdirectory: @"WILDObjectTemplates"];
}


-(WILDPart*)	createNewButtonNamed: (NSString*)inName
{
	WILDPart*	newPart = [self addNewPartFromXMLTemplate: [self URLForPartTemplate:@"ButtonPartTemplate"]];
	[newPart setName: inName];
	return newPart;
}


-(WILDPart*)	createNewFieldNamed: (NSString*)inName
{
	WILDPart*	newPart = [self addNewPartFromXMLTemplate: [self URLForPartTemplate:@"FieldPartTemplate"]];
	[newPart setName: inName];
	return newPart;
}


-(WILDPart*)	createNewMoviePlayerNamed: (NSString*)inName
{
	WILDPart*	newPart = [self addNewPartFromXMLTemplate: [self URLForPartTemplate:@"MoviePlayerPartTemplate"]];
	[newPart setName: inName];
	return newPart;
}


-(WILDPart*)	createNewBrowserNamed: (NSString*)inName
{
	WILDPart*	newPart = [self addNewPartFromXMLTemplate: [self URLForPartTemplate:@"BrowserPartTemplate"]];
	[newPart setName: inName];
	return newPart;
}


-(WILDPart*)	createNewButton: (id)sender
{
	return [self addNewPartFromXMLTemplate: [self URLForPartTemplate:@"ButtonPartTemplate"]];
}


-(WILDPart*)	createNewField: (id)sender
{
	return [self addNewPartFromXMLTemplate: [self URLForPartTemplate:@"FieldPartTemplate"]];
}


-(WILDPart*)	createNewMoviePlayer: (id)sender
{
	return [self addNewPartFromXMLTemplate: [self URLForPartTemplate:@"MoviePlayerPartTemplate"]];
}


-(WILDPart*)	createNewBrowser: (id)sender
{
	return [self addNewPartFromXMLTemplate: [self URLForPartTemplate:@"BrowserPartTemplate"]];
}


-(void)	deletePart: (WILDPart*)inPart
{
	[[NSNotificationCenter defaultCenter] postNotificationName: WILDLayerWillRemovePartNotification object: self userInfo: [NSDictionary dictionaryWithObjectsAndKeys: inPart, WILDAffectedPartKey, nil]];
	
	[mParts removeObject: inPart];
	[mAddColorParts removeObject: inPart];
	
	[self updateChangeCount: NSChangeDone];
}


-(WILDObjectID)	uniqueIDForPart
{
	BOOL				notUnique = YES;
	
	while( notUnique )
	{
		notUnique = NO;
		
		for( WILDPart* currPart in mParts )
		{
			if( [currPart partID] == mPartIDSeed )
			{
				notUnique = YES;
				mPartIDSeed++;
				break;
			}
		}
	}
	
	return mPartIDSeed;
}


-(NSUInteger)	numberOfPartsOfType: (NSString*)inPartType
{
	NSUInteger	partCount = 0;
	
	for( WILDPart* currPart in mParts )
	{
		if( [[currPart partType] isEqualToString: inPartType] )
			partCount++;
	}
	
	return partCount;
}


-(WILDPart*)	partAtIndex: (NSUInteger)inPartIndex ofType: (NSString*)inPartType
{
	NSUInteger	partCount = 0;
	WILDPart*	foundPart = nil;
	
	for( WILDPart* currPart in mParts )
	{
		if( inPartType == nil || [[currPart partType] isEqualToString: inPartType] )
		{
			if( partCount == inPartIndex )
			{
				foundPart = currPart;
				break;
			}
			partCount++;
		}
	}
	
	return foundPart;
}


-(NSUInteger)	indexOfPart: (WILDPart*)inPart asType: (NSString*)inPartType
{
	if( inPartType == nil )
		return [mParts indexOfObject: inPart];
	else
	{
		NSUInteger		partIdx = 0;
		for( WILDPart* currPart in mParts )
		{
			if( [[currPart partType] isEqualToString: inPartType] )
			{
				if( currPart == inPart )
					return partIdx;
				++partIdx;
			}
		}
	}
	
	return NSNotFound;
}


-(void)		movePart: (WILDPart*)inPart toIndex: (NSUInteger)inNewIndex asType: (NSString*)inPartType
{
	[inPart retain];
	if( inPartType == nil )
	{
		if( inNewIndex < (mParts.count -1) )
		{
			[mParts removeObject: inPart];
			[mParts insertObject: inPart atIndex: inNewIndex];
		}
	}
	else
	{
		NSUInteger		currIdx = [mParts indexOfObject: inPart];
		[mParts removeObject: inPart];
		WILDPart	*	precedingPartOfSameType = [self partAtIndex: ((inNewIndex > 0) ? inNewIndex -1 : 0) ofType: inPartType];
		NSUInteger		precedingIndex = precedingPartOfSameType ? [mParts indexOfObject: precedingPartOfSameType] : NSNotFound;
		NSUInteger		newIndex = currIdx;
		if( precedingIndex != NSNotFound )
			newIndex = precedingIndex +1;
		[mParts insertObject: inPart atIndex: newIndex];
	}
	[self updateChangeCount: NSChangeDone];
	[inPart release];
}

-(WILDPart*)	partNamed: (NSString*)inPartName ofType: (NSString*)inPartType
{
	WILDPart*	foundPart = nil;
	
	for( WILDPart* currPart in mParts )
	{
		if( inPartType == nil || [[currPart partType] isEqualToString: inPartType] )
		{
			if( [[currPart name] caseInsensitiveCompare: inPartName] == NSOrderedSame )
			{
				foundPart = currPart;
				break;
			}
		}
	}
	
	return foundPart;
}


-(WILDPart*)	addNewPartFromXMLTemplate: (NSURL*)xmlFile
{
	NSError			*	outError = nil;
	NSXMLDocument	*	templateDocument = [[[NSXMLDocument alloc] initWithContentsOfURL: xmlFile options: 0 error: &outError] autorelease];
	if( !templateDocument && outError )
	{
		UKLog(@"Couldn't load XML template for part: %@",outError);
		return nil;
	}
	
	NSXMLElement	*	theElement = [templateDocument rootElement];
	WILDPart		*	newPart = [[[WILDPart alloc] initWithXMLElement: theElement forStack: mStack] autorelease];
	
	[self addPart: newPart];
	return newPart;
}


-(void)	addPart: (WILDPart*)newPart
{
	WILDObjectID	theID = newPart.partID;
	if( [self partWithID: theID] != nil )	// Ensure we don't get duplicate IDs.
	{
		theID = [self uniqueIDForPart];
		[newPart setPartID: theID];
	}
	[newPart setPartLayer: [self partLayer]];
	[newPart setPartOwner: self];
	[newPart setStack: mStack];
	[mParts addObject: newPart];
	[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(partDidChange:) name:WILDPartDidChangeNotification object: newPart];
	
	[self updateChangeCount: NSChangeDone];
	[[NSNotificationCenter defaultCenter] postNotificationName: WILDLayerDidAddPartNotification
						object: self userInfo: [NSDictionary dictionaryWithObjectsAndKeys: newPart, WILDAffectedPartKey,
							nil]];
}


-(void)	addContents: (WILDPartContents*)inContents
{
	NSString*	theKey = [NSString stringWithFormat: @"%@:%lld", [inContents partLayer], [inContents partID]];
	[mContents setObject: inContents forKey: theKey];
}


-(WILDStack*)	stack
{
	return mStack;
}


-(void)	appendInnerAddColorObjectXmlToString: (NSMutableString*)theString
{
	// TODO: Implement writing of AddColor data.
}


-(void)	appendInnerXmlToString: (NSMutableString*)theString
{
	[theString appendFormat: @"\t<id>%lld</id>\n", mID];
	[theString appendFormat: @"\t<name>%@</name>\n", WILDStringEscapedForXML(mName)];
	[theString appendFormat: @"\t<showPict>%@</showPict>\n", mShowPict ? @"<true />" : @"<false />"];
	[theString appendFormat: @"\t<cantDelete>%@</cantDelete>\n", mCantDelete ? @"<true />" : @"<false />"];
	[theString appendFormat: @"\t<dontSearch>%@</dontSearch>\n", mDontSearch ? @"<true />" : @"<false />"];
	if( mPictureName )
		[theString appendFormat: @"\t<bitmap>%@</bitmap>\n", mPictureName];
	[theString appendFormat: @"\t<script>%@</script>\n", WILDStringEscapedForXML(mScript)];
	
	[theString appendString: @"\t<userProperties>\n"];
	for( NSString *userPropName in [[mUserProperties allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)] )
	{
		WILDAppendStringXML( theString, 2, userPropName, @"name" );
		WILDAppendStringXML( theString, 2, mUserProperties[userPropName], @"value" );
	}
	[theString appendString: @"\t</userProperties>\n"];
	
	for( WILDPart* currPart in mParts )
	{
		[theString appendString: [currPart xmlString]];
	}
	
	for( WILDPartContents* currContents in [mContents allValues] )
	{
		[theString appendString: [currContents xmlString]];
	}
	
	[self appendInnerAddColorObjectXmlToString: theString];
}


-(NSString*)	xmlStringForWritingToURL: (NSURL*)packageURL forSaveOperation:(NSSaveOperationType)saveOperation originalContentsURL:(NSURL *)absoluteOriginalContentsURL error: (NSError**)outError
{
	if( mPictureName && !mPicture )
	{
		NSURL		*	oldPictureURL = [absoluteOriginalContentsURL URLByAppendingPathComponent: mPictureName];
		NSURL		*	pictureURL = [packageURL URLByAppendingPathComponent: mPictureName];
		BOOL			fileAlreadyThere = [[NSFileManager defaultManager] fileExistsAtPath: [pictureURL path]];
		NSError		*	theError = nil;
		BOOL			success = NO;
		
		if( !fileAlreadyThere && (saveOperation == NSSaveOperation || saveOperation == NSAutosaveOperation) )
		{
			success = [[NSFileManager defaultManager] linkItemAtPath: [oldPictureURL path] toPath: [pictureURL path] error: &theError];
		}
		if( !success && !fileAlreadyThere )
		{
			success = [[NSFileManager defaultManager] copyItemAtPath: [oldPictureURL path] toPath: [pictureURL path] error: &theError];
		}
		if( !success )
			return nil;
	}
	else if( mPicture )
	{
		if( !mPictureName )
			mPictureName = [[NSString stringWithFormat: @"bitmap_%lld",mID] retain];
		ASSIGN(mPictureName,[[mPictureName stringByDeletingPathExtension] stringByAppendingPathExtension: @"tiff"]);
		NSURL*	pictureURL = [packageURL URLByAppendingPathComponent: mPictureName];
		if( ![[mPicture TIFFRepresentation] writeToURL: pictureURL atomically: YES] )
			return nil;
	}

	NSMutableString	*	theString = [NSMutableString stringWithFormat: @"<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n"
												"<!DOCTYPE %1$@ PUBLIC \"-//Apple, Inc.//DTD %1$@ V 2.0//EN\" \"\" >\n"
																		"<%1$@>\n", [self partLayer]];
	
	[self appendInnerXmlToString: theString];	// Hook-in point for subclasses (like WILDCard).
	
	[theString appendFormat: @"</%@>\n", [self partLayer]];
		
	return theString;
}


-(void)	updateChangeCount: (NSDocumentChangeType)inChange
{
	[[mStack document] updateChangeCount: inChange];
}


-(void)	partDidChange: (NSNotification*)notif
{
	WILDPart	*	thePart = [notif object];
	NSString	*	propName = [[notif userInfo] objectForKey: WILDAffectedPropertyKey];
	SEL				theAction = NSSelectorFromString( [propName stringByAppendingString: @"PropertyDidChangeOfPart:"] );
	if( [self respondsToSelector: theAction] )
		[self performSelector: theAction withObject: thePart];
}


-(void)	familyPropertyDidChangeOfPart: (WILDPart*)thePart
{
	[mButtonFamilies removeObject: thePart];
	[mButtonFamilies addObject: thePart forKey: [NSNumber numberWithInteger: [thePart family]]];
}


-(void)	bringPartCloser: (WILDPart*)inPart
{
	NSUInteger	theIndex = [mParts indexOfObject: inPart];
	if( theIndex < ([mParts count] -1) )
	{
		[[inPart retain] autorelease];
		[mParts removeObjectAtIndex: theIndex];
		[mParts insertObject: inPart atIndex: theIndex +1];
	}
	
	[self updateChangeCount: NSChangeDone];
}


-(void)	sendPartFarther: (WILDPart*)inPart
{
	NSUInteger	theIndex = [mParts indexOfObject: inPart];
	if( theIndex > 0 )
	{
		[[inPart retain] autorelease];
		[mParts removeObjectAtIndex: theIndex];
		[mParts insertObject: inPart atIndex: theIndex -1];
	}
	
	[self updateChangeCount: NSChangeDone];
}


-(NSString*)	script
{
	return mScript;
}


-(void)	setScript: (NSString*)theScript
{
	ASSIGN(mScript,theScript);
	if( mScriptObject )
	{
		LEOScriptRelease( mScriptObject );
		mScriptObject = NULL;
	}
}


-(void)	getID: (LEOObjectID*)outID seedForScripts: (LEOObjectSeed*)outSeed
{
	if( mIDForScripts == kLEOObjectIDINVALID )
	{
		LEOInitWILDObjectValue( &mValueForScripts, self, kLEOInvalidateReferences, NULL );
		mIDForScripts = LEOContextGroupCreateNewObjectIDForPointer( [mStack scriptContextGroupObject], &mValueForScripts );
		mSeedForScripts = LEOContextGroupGetSeedForObjectID( [mStack scriptContextGroupObject], mIDForScripts );
	}
	
	if( mIDForScripts )
	{
		if( outID )
			*outID = mIDForScripts;
		if( outSeed )
			*outSeed = mSeedForScripts;
	}
}


-(struct LEOScript*)	scriptObjectShowingErrorMessage: (BOOL)showError
{
	if( !mScriptObject )
	{
		if( !mScript )
			return NULL;
		const char*		scriptStr = [mScript UTF8String];
		uint16_t		fileID = LEOFileIDForFileName( [[self displayName] UTF8String] );
		LEOParseTree*	parseTree = LEOParseTreeCreateFromUTF8Characters( scriptStr, strlen(scriptStr), fileID );
		if( LEOParserGetLastErrorMessage() == NULL )
		{
			[self getID: NULL seedForScripts: NULL];	// Make sure ivars mIDForScripts and mSeedForScripts are initialized.
			mScriptObject = LEOScriptCreateForOwner( mIDForScripts, mSeedForScripts, LEOForgeScriptGetParentScript );
			LEOScriptCompileAndAddParseTree( mScriptObject, [mStack scriptContextGroupObject], parseTree, fileID );
			
			#if REMOTE_DEBUGGER
			LEORemoteDebuggerAddFile( scriptStr, fileID, mScriptObject );
			
			// Set a breakpoint on the mouseUp handler:
//			LEOHandlerID handlerName = LEOContextGroupHandlerIDForHandlerName( [mStack scriptContextGroupObject], "mouseup" );
//			LEOHandler* theHandler = LEOScriptFindCommandHandlerWithID( mScriptObject, handlerName );
//			if( theHandler )
//				LEORemoteDebuggerAddBreakpoint( theHandler->instructions );
			#endif
		}
		if( LEOParserGetLastErrorMessage() )
		{
			if( showError && [NSApp isRunning] )
				NSRunAlertPanel( @"Script Error", @"%@", @"OK", @"", @"", [NSString stringWithCString: LEOParserGetLastErrorMessage() encoding: NSUTF8StringEncoding] );
			if( mScriptObject )
			{
				LEOScriptRelease( mScriptObject );
				mScriptObject = NULL;
			}
		}
	}
	
	return mScriptObject;
}


-(struct LEOContextGroup*)	scriptContextGroupObject
{
	return [[mStack document] scriptContextGroupObject];
}


-(NSString*)	textContents
{
	return nil;
}


-(BOOL)			setTextContents: (NSString*)inString
{
	return NO;
}

-(BOOL)			goThereInNewWindow: (BOOL)inNewWindow
{
	return NO;
}

-(id)	valueForWILDPropertyNamed: (NSString*)inPropertyName ofRange: (NSRange)byteRange
{
	if( [inPropertyName isEqualToString: @"short name"] || [inPropertyName isEqualToString: @"name"] )
	{
		return [self name];
	}
	else
		return [mUserProperties objectForKey: inPropertyName];
}


-(BOOL)		setValue: (id)inValue forWILDPropertyNamed: (NSString*)inPropertyName inRange: (NSRange)byteRange
{
	BOOL	propExists = YES;
	
	[[NSNotificationCenter defaultCenter] postNotificationName: WILDLayerWillChangeNotification
							object: self userInfo: [NSDictionary dictionaryWithObject: inPropertyName
															forKey: WILDAffectedPropertyKey]];
	if( [inPropertyName isEqualToString: @"short name"] || [inPropertyName isEqualToString: @"name"] )
		[self setName: inValue];
	else
	{
		id		theValue = [mUserProperties objectForKey: inPropertyName];
		if( theValue )
			[mUserProperties setObject: inValue forKey: inPropertyName];
		else
			propExists = NO;
	}

	[[NSNotificationCenter defaultCenter] postNotificationName: WILDLayerDidChangeNotification
							object: self userInfo: [NSDictionary dictionaryWithObject: inPropertyName
															forKey: WILDAffectedPropertyKey]];
	if( propExists )
		[self updateChangeCount: NSChangeDone];
	
	return propExists;
}


-(LEOValueTypePtr)	typeForWILDPropertyNamed: (NSString*)inPropertyName;
{
	return &kLeoValueTypeString;
}


-(void)	addUserPropertyNamed: (NSString*)userPropName
{
	if( !mUserProperties )
		mUserProperties = [[NSMutableDictionary alloc] init];
	if( ![mUserProperties objectForKey: userPropName] )
	{
		[mUserProperties setObject: @"" forKey: userPropName];
		[self updateChangeCount: NSChangeDone];
	}
}


-(void)	deleteUserPropertyNamed: (NSString*)userPropName
{
	if( [mUserProperties objectForKey: userPropName] )
	{
		[mUserProperties removeObjectForKey: userPropName];
		[self updateChangeCount: NSChangeDone];
	}
}


-(id<WILDObject>)	parentObject
{
	return nil;
}

-(NSString*)	displayName
{
	if( mName && [mName length] > 0 )
		return [NSString stringWithFormat: @"background “%1$@” (ID %2$lld)", mName, mID];
	else
		return [NSString stringWithFormat: @"background ID %1$lld", mID];
}


-(NSImage*)	displayIcon
{
	return [NSImage imageNamed: @"BackgroundIconSmall"];
}


-(NSString*)	description
{
	return [NSString stringWithFormat: @"%@ {\nid = %lld\nname = %@\nparts = %@\n}", [self class], mID, mName, mParts];
}

@end
