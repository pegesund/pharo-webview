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

{ #category : 'compositing' }
WebViewFormRenderer >> compositeAll [
	"Assumes mutex held. World texture drawn first (opaque XRGB), then each browser
	overlay ON TOP but clipped away from the device rects of morphs in front of it
	in z-order — so a morph placed over the browser occludes it (real z-order)."
	renderer copy: texture.
	overlays ifNotNil: [
		overlays do: [ :entry |
			[ (self validateEntry: entry) ifTrue: [ self drawOverlayOccluded: entry ] ]
				on: Error
				do: [ :e | entry at: #pixels put: nil.
					WebViewProjectPlan log: 'compositeAll entry ERROR: ', e printString ] ] ]
]

{ #category : 'updating screen' }
WebViewFormRenderer >> copyAndPresentTextureRectangle: rectangle [
	"Full recomposite each present: world texture, then occlusion-clipped browser
	overlays. The dirty rectangle is ignored because overlays span it arbitrarily."
	deferUpdates ifTrue: [ ^ self ].
	self compositeAll.
	renderer present
]

{ #category : 'deleting' }
WebViewFormRenderer >> destroy [
	mutex critical: [
		overlays ifNotNil: [ overlays do: [ :entry | (entry at: #texture ifAbsent: [nil]) ifNotNil: [:t | t destroy ] ] ].
		overlays := OrderedCollection new ].
	super destroy
]

{ #category : 'compositing' }
WebViewFormRenderer >> drawOverlayOccluded: entry [
	"Draw this browser overlay clipped away from the device rects of morphs in front
	of it in z-order (real occlusion). Bounds + visible rects are integer-aligned and
	the source rect uses consistent corner rounding, so there is no sub-pixel seam."
	| tex texExtent bounds occluders visible sx sy |
	tex := entry at: #texture.
	texExtent := entry at: #textureExtent.
	bounds := ((entry at: #bounds) origin rounded) corner: ((entry at: #bounds) corner rounded).
	occluders := self occludersFor: (entry at: #key) target: bounds.
	visible := OrderedCollection with: bounds.
	occluders do: [ :occ | | next |
		next := OrderedCollection new.
		visible do: [ :v | next addAll: (v areasOutside: occ) ].
		visible := next ].
	sx := texExtent x / (bounds width max: 1).
	sy := texExtent y / (bounds height max: 1).
	visible do: [ :v |
		v area > 0 ifTrue: [ | src so sc |
			so := ((v origin - bounds origin) * (sx @ sy)) rounded.
			sc := ((v corner - bounds origin) * (sx @ sy)) rounded.
			src := so corner: sc.
			renderer copy: tex srcRect: src asSDLRect dstRect: v asSDLRect.
			overlayCopyCount := (overlayCopyCount ifNil: [ 0 ]) + 1 ] ]
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

{ #category : 'compositing' }
WebViewFormRenderer >> occludersFor: morph target: deviceBounds [
	"Device rects of morphs in front of `morph` at any ancestor level whose device
	bounds overlap deviceBounds. Occluders are rounded OUTWARD (floor origin, ceil
	corner) so they fully cover the morph with no sub-pixel seam the browser texture
	could bleed through."
	| result scale cur |
	result := OrderedCollection new.
	scale := OSWorldRenderer canvasScaleFactor.
	cur := morph.
	[ cur notNil and: [ cur owner notNil ] ] whileTrue: [
		| owner sibs idx |
		owner := cur owner.
		sibs := owner submorphs.
		idx := sibs indexOf: cur.
		idx > 0 ifTrue: [
			1 to: idx - 1 do: [ :i | | sm dr |
				sm := sibs at: i.
				sm visible ifTrue: [
					dr := ((sm fullBounds origin * scale) floor) corner: ((sm fullBounds corner * scale) ceiling).
					(dr intersects: deviceBounds) ifTrue: [ result add: dr ] ] ] ].
		cur := owner ].
	^ result
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
		self compositeAll.
		renderer present ]
]

{ #category : 'private' }
WebViewFormRenderer >> useDeferredUpdates [
	mutex critical: [ self compositeAll. renderer present ]
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
