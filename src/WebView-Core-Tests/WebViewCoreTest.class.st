Class {
	#name : 'WebViewCoreTest',
	#superclass : 'TestCase',
	#category : 'WebView-Core-Tests',
	#package : 'WebView-Core-Tests'
}

{ #category : 'tests' }
WebViewCoreTest >> testCdpInputWiring [
	self assert: (WebViewCdpMorph includesSelector: #mouseDown:).
	self assert: (WebViewCdpMorph includesSelector: #toBrowserCoords:).
	self assert: (WebViewCdpMorph includesSelector: #writeCommand:).
	self assert: (WebViewCdpMorph includesSelector: #keyStroke:)
]

{ #category : 'tests' }
WebViewCoreTest >> testCdpMorphWiring [
	self assert: (WebViewCdpMorph includesSelector: #step).
	self assert: (WebViewCdpMorph includesSelector: #loadCurrentFrame).
	self assert: (WebViewCdpMorph includesSelector: #pushForm:).
	"decode path is available"
	self assert: (Smalltalk includesKey: #ImageReadWriter)
]

{ #category : 'tests' }
WebViewCoreTest >> testCefMorphVisibility [
	self assert: (WebViewCefMorph includesSelector: #hide).
	self assert: (WebViewCefMorph includesSelector: #show).
	self assert: (WebViewCefMorph includesSelector: #maybeResize).
	self assert: (WebViewCefMorph includesSelector: #launchHost).
	self assert: (WebViewCefMorph includesSelector: #killHost)
]

{ #category : 'tests' }
WebViewCoreTest >> testFormRendererMultiOverlay [
	self assert: (WebViewFormRenderer includesSelector: #overlayFor:pixels:extent:pitch:bounds:dirtyRects:).
	self assert: (WebViewFormRenderer includesSelector: #removeOverlayFor:).
	self assert: (WebViewFormRenderer includesSelector: #validateEntry:).
	self assert: (WebViewCefMorph includesSelector: #pushFrame)
]

{ #category : 'tests' }
WebViewCoreTest >> testFormRendererOverridesAllPresentSites [
	#(copyAndPresentTextureRectangle: updateAll useDeferredUpdates copyOverlay clearOverlay overlayFor:pixels:extent:pitch:bounds:dirtyRects: removeOverlayFor: destroy)
		do: [ :sel | self assert: (WebViewFormRenderer includesSelector: sel) description: sel asString ]
]

{ #category : 'tests' }
WebViewCoreTest >> testPatternMorphRendersWithoutWorld [
	| m |
	m := WebViewTestPatternMorph new.
	m renderPattern.
	m step.
	self assert: m extent equals: 320 @ 240.
	m delete
]

{ #category : 'tests' }
WebViewCoreTest >> testPlanM0IsDone [
	self assert: (WebViewProjectPlan status at: #M0) equals: #done.
	self assert: (WebViewProjectPlan reportAt: #M0) isNotNil
]

{ #category : 'tests' }
WebViewCoreTest >> testShimRoundTrip [
	| s |
	s := WvShim new.
	s openExtent: 64 @ 48.
	self assert: s isOpen.
	(Delay forMilliseconds: 120) wait.
	s tick.
	self assert: s frameReady.
	self assert: s frameWidth equals: 64.
	self assert: s frameHeight equals: 48.
	self assert: s frameBuffer isNil not.
	self assert: s dirtyRects isEmpty not.
	s frameAck.
	self deny: s frameReady.
	s destroy.
	self deny: s isOpen
]

{ #category : 'tests' }
WebViewCoreTest >> testShimVersion [
	self assert: WvShim version equals: 1
]

{ #category : 'tests' }
WebViewCoreTest >> testWorldRendererRegistration [
	self assert: WebViewWorldRenderer priority equals: 3.
	self deny: (WebViewWorldRenderer isApplicableFor: nil).
	self assert: (AbstractWorldRenderer allSubclasses includes: WebViewWorldRenderer)
]
