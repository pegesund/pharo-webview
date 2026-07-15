Class {
	#name : 'WebViewFormRenderer',
	#superclass : 'OSSDL2FormRenderer',
	#instVars : [
		'overlays',
		'overlayCopyCount'
	],
	#category : 'WebView-Core',
	#package : 'WebView-Core'
}

{ #category : 'installation' }
WebViewFormRenderer class >> install [
	| bw old new |
	bw := (nil currentWorld worldState worldRenderer instVarNamed: 'osWindow') instVarNamed: 'backendWindow'.
	old := bw renderer.
	(old isKindOf: WebViewFormRenderer) ifTrue: [ ^ old ].
	new := self new.
	new adoptStateFrom: old.
	bw renderer: new.
	WebViewProjectPlan log: 'WebViewFormRenderer installed'.
	^ new
]

{ #category : 'installation' }
WebViewFormRenderer class >> probeSdlOverlayPath [
	"Diagnostic: exercise every SDL call the overlay path uses, on the LIVE renderer,
	without swapping anything. Run deferred on the UI process. Results go to the log."
	| fr sdlr form tex fmt acc |
	[
	fr := nil currentWorld worldState worldRenderer osWindowRenderer.
	sdlr := fr instVarNamed: 'renderer'.
	WebViewProjectPlan log: 'probe: start'.
	form := Form extent: 64 @ 64 depth: 32.
	form getCanvas fillRectangle: (0 @ 0 extent: 64 @ 64) color: Color red.
	fmt := SDL2Constants classPool at: #SDL_PIXELFORMAT_XRGB8888.
	acc := SDL2Constants classPool at: #SDL_TEXTUREACCESS_STREAMING.
	tex := sdlr createTextureFormat: fmt access: acc width: 64 height: 64.
	WebViewProjectPlan log: 'probe: texture created'.
	tex updateTexturePixels: form bits pitch: 64 * 4.
	WebViewProjectPlan log: 'probe: upload ok'.
	sdlr copy: (fr instVarNamed: 'texture').
	sdlr copy: tex srcRect: (0 @ 0 extent: 64 @ 64) asSDLRect dstRect: (100 @ 100 extent: 64 @ 64) asSDLRect.
	WebViewProjectPlan log: 'probe: copy ok'.
	sdlr present.
	WebViewProjectPlan log: 'probe: present ok'.
	tex destroy.
	WebViewProjectPlan log: 'probe: destroy ok - PROBE PASSED' ]
		on: Error
		do: [ :e | WebViewProjectPlan log: 'probe FAILED: ', e printString ]
]

{ #category : 'installation' }
WebViewFormRenderer class >> revert [
	| bw cur old |
	bw := (nil currentWorld worldState worldRenderer instVarNamed: 'osWindow') instVarNamed: 'backendWindow'.
	cur := bw renderer.
	(cur isKindOf: WebViewFormRenderer) ifFalse: [ ^ self ].
	old := OSSDL2FormRenderer new.
	#(form backendWindow renderer texture extent deferUpdates mutex)
		do: [ :iv | old instVarNamed: iv put: (cur instVarNamed: iv) ].
	bw renderer: old.
	WebViewProjectPlan log: 'reverted to OSSDL2FormRenderer'
]

{ #category : 'installation' }
WebViewFormRenderer >> adoptStateFrom: anOSSDL2FormRenderer [
	#(form backendWindow renderer texture extent deferUpdates mutex)
		do: [ :iv | self instVarNamed: iv put: (anOSSDL2FormRenderer instVarNamed: iv) ]
]

{ #category : 'overlay' }
WebViewFormRenderer >> clearOverlay [
	mutex critical: [
		overlays ifNotNil: [
			overlays do: [ :entry | (entry at: #texture ifAbsent: [ nil ]) ifNotNil: [ :t | t destroy ] ] ].
		overlays := OrderedCollection new ]
]

{ #category : 'updating screen' }
WebViewFormRenderer >> copyAndPresentTextureRectangle: rectangle [
	| sdlRectangle |
	deferUpdates ifTrue: [ ^ self ].
	sdlRectangle := rectangle asSDLRect.
	renderer copy: texture srcRect: sdlRectangle dstRect: sdlRectangle.
	self copyOverlay.
	renderer present
]

{ #category : 'overlay' }
WebViewFormRenderer >> copyOverlay [
	"Assumes mutex held. Composite every overlay entry (in z-order) after the world
	texture copy, before present. Per-entry errors kill-switch that entry only."
	overlays ifNil: [ ^ self ].
	overlays do: [ :entry |
		[ (self validateEntry: entry) ifTrue: [
			renderer
				copy: (entry at: #texture)
				srcRect: (0 @ 0 extent: (entry at: #textureExtent)) asSDLRect
				dstRect: (entry at: #bounds) asSDLRect.
			overlayCopyCount := (overlayCopyCount ifNil: [ 0 ]) + 1 ] ]
			on: Error
			do: [ :e |
				entry at: #pixels put: nil.
				WebViewProjectPlan log: 'copyOverlay entry ERROR: ', e printString ] ]
]

{ #category : 'deleting' }
WebViewFormRenderer >> destroy [
	mutex critical: [
		overlays ifNotNil: [ overlays do: [ :entry | (entry at: #texture ifAbsent: [nil]) ifNotNil: [:t | t destroy ] ] ].
		overlays := OrderedCollection new ].
	super destroy
]

{ #category : 'overlay' }
WebViewFormRenderer >> entryFor: aKey [
	"Find or create the overlay entry (a Dictionary) for aKey. Assumes mutex held."
	overlays ifNil: [ overlays := OrderedCollection new ].
	^ overlays detect: [ :e | (e at: #key) == aKey ] ifNone: [
		| entry |
		entry := IdentityDictionary new.
		entry at: #key put: aKey; at: #dirty put: false.
		overlays add: entry.
		entry ]
]

{ #category : 'initialization' }
WebViewFormRenderer >> initialize [
	super initialize.
	overlays := OrderedCollection new.
	overlayCopyCount := 0
]

{ #category : 'accessing' }
WebViewFormRenderer >> overlayCopyCount [ ^ overlayCopyCount ifNil: [ 0 ]
]

{ #category : 'accessing' }
WebViewFormRenderer >> overlayCount [ ^ overlays ifNil: [ 0 ] ifNotNil: [ overlays size ]
]

{ #category : 'overlay' }
WebViewFormRenderer >> overlayFor: aKey pixels: pixelsSource extent: aPoint pitch: pitchInt bounds: aRectangle dirtyRects: rectsOrNil [
	"Register/update the overlay for aKey. pixelsSource is an ExternalAddress or a
	Form Bitmap; bounds is the destination rect in texture (device) coordinates."
	mutex critical: [
		| entry |
		entry := self entryFor: aKey.
		entry at: #pixels put: pixelsSource.
		entry at: #pixelExtent put: aPoint.
		entry at: #pitch put: pitchInt.
		entry at: #bounds put: aRectangle.
		entry at: #dirtyRects put: rectsOrNil.
		entry at: #dirty put: true ]
]

{ #category : 'overlay' }
WebViewFormRenderer >> overlayForm: aForm bounds: aRectangle [
	self overlayPixels: aForm bits extent: aForm extent pitch: aForm width * 4 bounds: aRectangle dirtyRects: nil
]

{ #category : 'overlay' }
WebViewFormRenderer >> overlayPixels: pixelsSource extent: aPoint pitch: pitchInt bounds: aRectangle dirtyRects: aCollectionOrNil [
	"Set the overlay source. pixelsSource: an ExternalAddress (engine buffer) or a Bitmap
	(Form bits). bounds is the destination rect in texture coordinates. dirtyRects (source
	coordinates) enable per-rect upload; nil means full upload. Called from the UI process."
	mutex critical: [
		overlayPixels := pixelsSource.
		overlayPixelExtent := aPoint.
		overlayPitch := pitchInt.
		overlayBounds := aRectangle.
		overlayDirtyRects := aCollectionOrNil.
		overlayDirty := true ]
]

{ #category : 'overlay' }
WebViewFormRenderer >> removeOverlayFor: aKey [
	mutex critical: [
		overlays ifNil: [ ^ self ].
		(overlays detect: [ :e | (e at: #key) == aKey ] ifNone: [ nil ]) ifNotNil: [ :entry |
			(entry at: #texture ifAbsent: [ nil ]) ifNotNil: [ :t | t destroy ].
			overlays remove: entry ifAbsent: [ ] ] ]
]

{ #category : 'updating screen' }
WebViewFormRenderer >> updateAll [
	mutex critical: [
		self validate ifFalse: [ ^ self ].
		texture updateTexturePixels: form bits pitch: form width * 4.
		deferUpdates ifTrue: [ ^ self ].
		renderer copy: texture.
		self copyOverlay.
		renderer present ]
]

{ #category : 'private' }
WebViewFormRenderer >> useDeferredUpdates [
	mutex critical: [ renderer copy: texture. self copyOverlay. renderer present ]
]

{ #category : 'overlay' }
WebViewFormRenderer >> validateEntry: entry [
	"Assumes mutex held and renderer valid. (Re)creates + uploads this entry texture,
	using per-dirty-rect upload when dirty rects are supplied and the source is an
	ExternalAddress; otherwise a full upload."
	| pixels pxExtent tex |
	pixels := entry at: #pixels ifAbsent: [ nil ].
	pixels ifNil: [ ^ false ].
	pxExtent := entry at: #pixelExtent.
	tex := entry at: #texture ifAbsent: [ nil ].
	(tex isNil or: [ tex isNull or: [ (entry at: #textureExtent ifAbsent: [ nil ]) ~= pxExtent ] ]) ifTrue: [
		tex ifNotNil: [ tex destroy ].
		tex := renderer
			createTextureFormat: SDL_PIXELFORMAT_XRGB8888
			access: SDL_TEXTUREACCESS_STREAMING
			width: pxExtent x height: pxExtent y.
		entry at: #texture put: tex.
		entry at: #textureExtent put: pxExtent.
		entry at: #dirty put: true.
		entry at: #dirtyRects put: nil ].
	(entry at: #dirty) ifTrue: [
		| dr pitch |
		dr := entry at: #dirtyRects ifAbsent: [ nil ].
		pitch := entry at: #pitch.
		(dr isNil or: [ dr isEmpty or: [ (pixels isKindOf: ExternalAddress) not ] ])
			ifTrue: [ tex updateTexturePixels: pixels pitch: pitch ]
			ifFalse: [
				dr do: [ :rct | | clipped ptr |
					clipped := rct intersect: (0 @ 0 extent: pxExtent) ifNone: [ nil ].
					clipped ifNotNil: [
						ptr := pixels + (clipped origin y * pitch) + (clipped origin x * 4).
						tex updateTextureRect: clipped asSDLRect pixels: ptr pitch: pitch ] ] ].
		entry at: #dirty put: false ].
	^ true
]

{ #category : 'overlay' }
WebViewFormRenderer >> validateOverlay [
	"Assumes mutex is held and renderer is valid. (Re)creates the overlay texture and
	uploads pending pixels - per dirty rect when possible, else the full buffer."
	overlayPixels ifNil: [ ^ false ].
	(overlayTexture isNil or: [ overlayTexture isNull or: [ overlayTextureExtent ~= overlayPixelExtent ] ]) ifTrue: [
		overlayTexture ifNotNil: [ overlayTexture destroy ].
		overlayTexture := renderer
			createTextureFormat: SDL_PIXELFORMAT_XRGB8888
			access: SDL_TEXTUREACCESS_STREAMING
			width: overlayPixelExtent x
			height: overlayPixelExtent y.
		overlayTextureExtent := overlayPixelExtent.
		overlayDirtyRects := nil.
		overlayDirty := true ].
	overlayDirty ifTrue: [
		(overlayDirtyRects isNil or: [ overlayDirtyRects isEmpty or: [ (overlayPixels isKindOf: ExternalAddress) not ] ])
			ifTrue: [ overlayTexture updateTexturePixels: overlayPixels pitch: overlayPitch ]
			ifFalse: [
				overlayDirtyRects do: [ :r |
					| clipped ptr |
					clipped := r intersect: (0 @ 0 extent: overlayPixelExtent) ifNone: [ nil ].
					clipped ifNotNil: [
						ptr := overlayPixels + (clipped origin y * overlayPitch) + (clipped origin x * 4).
						overlayTexture updateTextureRect: clipped asSDLRect pixels: ptr pitch: overlayPitch ] ] ].
		overlayDirty := false.
		overlayDirtyRects := nil ].
	^ true
]
