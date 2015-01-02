//
//  CCard.h
//  Stacksmith
//
//  Created by Uli Kusterer on 2013-12-29.
//  Copyright (c) 2013 Uli Kusterer. All rights reserved.
//

#ifndef __Stacksmith__CCard__
#define __Stacksmith__CCard__

#include "CPlatformLayer.h"


namespace Carlson {

class CBackground;


typedef enum
{
    EVisualEffectSpeedVerySlow,
    EVisualEffectSpeedSlow,
    EVisualEffectSpeedNormal,
    EVisualEffectSpeedFast,
    EVisualEffectSpeedVeryFast
} TVisualEffectSpeed;


class CCard : public CPlatformLayer
{
public:
	CCard( std::string inURL, ObjectID inID, const std::string& inName, const std::string& inFileName, CStack* inStack, bool inMarked ) : CPlatformLayer(inURL,inID,inName,inFileName,inStack), mMarked(inMarked), mOwningBackground(NULL), mSpeed(EVisualEffectSpeedNormal)	{};
	~CCard();
	
	bool			IsMarked()					{ return mMarked; };
	void			SetMarked( bool inMarked );
	
	virtual void	WakeUp();
	virtual void	GoToSleep();
	
	virtual void	SetTransitionTypeAndSpeed( const std::string& inType, TVisualEffectSpeed inSpeed ) {  mTransitionType = inType; mSpeed = inSpeed; };
	
	virtual void	SetPeeking( bool inState );
	
	virtual CScriptableObject*	GetParentObject();
	virtual CBackground*		GetBackground()		{ return mOwningBackground; };
	virtual void				SetBackground( CBackground* inBg )	{ mOwningBackground = inBg; };	// Used mainly for assigning a background to a newly-created, never-before saved card in RAM.
	
	virtual bool				GoThereInNewWindow( TOpenInMode inOpenInMode, CStack* oldStack, CPart* overPart, std::function<void()> completionHandler );
	virtual bool				GetPropertyNamed( const char* inPropertyName, size_t byteRangeStart, size_t byteRangeEnd, LEOContext* inContext, LEOValuePtr outValue );
	virtual bool				SetValueForPropertyNamed( LEOValuePtr inValue, LEOContext* inContext, const char* inPropertyName, size_t byteRangeStart, size_t byteRangeEnd );
	
	virtual std::string			GetDisplayName();

	virtual void	CorrectRectOfPart( CPart* inMovedPart, THitPart partsToCorrect, long long *ioLeft, long long *ioTop, long long *ioRight, long long *ioBottom, std::function<void(long long inGuidelineCoord,TGuidelineCallbackAction action)> addGuidelineBlock );	// addGuidelineBlock gets called to create guidelines.
	
protected:
	virtual void	LoadPropertiesFromElement( tinyxml2::XMLElement* root );
	virtual void	SavePropertiesToElement( tinyxml2::XMLElement* stackfile );
	virtual void	CallAllCompletionBlocks();
	virtual const char*	GetLayerXMLType()			{ return "card"; };

	virtual const char*	GetIdentityForDump()		{ return "Card"; };

protected:
	bool			    mMarked;
	CBackground	*	    mOwningBackground;
	std::string		    mTransitionType;
    TVisualEffectSpeed	mSpeed;
};

typedef CRefCountedObjectRef<CCard>	CCardRef;

}

#endif /* defined(__Stacksmith__CCard__) */
