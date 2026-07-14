Class {
	#name : 'WebViewFormRenderer',
	#superclass : 'OSSDL2FormRenderer',
	#instVars : [
		'overlayTexture',
		'overlayForm',
		'overlayBounds',
		'overlayExtent',
		'overlayDirty',
		'overlayCopyCount'
	],
	#category : 'WebView-Core',
	#package : 'WebView-Core'
}

{ #category : 'installation' }
WebViewFormRenderer class >> install [
	"Swap the active form renderer for a WebViewFormRenderer by adopting its state.
	MUST run on the UI process (defer it). Returns the new renderer."
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
	"Swap back to a plain OSSDL2FormRenderer (state adopted). MUST run on the UI process."
	| bw cur old |
	bw := (nil currentWorld worldState worldRenderer instVarNamed: 'osWindow') instVarNamed: 'backendWindow'.
	cur := bw renderer.
	old := OSSDL2FormRenderer new.
	#(form backendWindow renderer texture extent deferUpdates mutex)
		do: [ :iv | old instVarNamed: iv put: (cur instVarNamed: iv) ].
	bw renderer: old.
	WebViewProjectPlan log: 'reverted to OSSDL2FormRenderer'
]

{ #category : 'installation' }
WebViewFormRenderer >> adoptStateFrom: anOSSDL2FormRenderer [
	"Take over the live SDL handles and mutex of an existing form renderer.
	No SDL teardown/re-creation - the swap is pure object surgery."
	#(form backendWindow renderer texture extent deferUpdates mutex)
		do: [ :iv | self instVarNamed: iv put: (anOSSDL2FormRenderer instVarNamed: iv) ]
]

{ #category : 'overlay' }
WebViewFormRenderer >> clearOverlay [
	mutex critical: [
		overlayTexture ifNotNil: [ overlayTexture destroy ].
		overlayTexture := nil.
		overlayForm := nil.
		overlayBounds := nil.
		overlayExtent := nil.
		overlayDirty := false ]
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
	"Assumes mutex is held. Interleave the overlay texture after the world texture copy,
	before present. Errors here must NEVER escape: an exception inside the caller mutex
	critical: block poisons the mutex (Pharo issue 10156) and freezes the UI.
	On any error: kill-switch the overlay and log."
	overlayBounds ifNil: [ ^ self ].
	[
	self validateOverlay ifTrue: [
		renderer
			copy: overlayTexture
			srcRect: (0 @ 0 extent: overlayExtent) asSDLRect
			dstRect: overlayBounds asSDLRect.
		overlayCopyCount := (overlayCopyCount ifNil: [ 0 ]) + 1 ] ]
		on: Error
		do: [ :e |
			overlayBounds := nil.
			WebViewProjectPlan log: 'copyOverlay ERROR (overlay disabled): ', e printString ]
]

{ #category : 'deleting' }
WebViewFormRenderer >> destroy [
	mutex critical: [
		overlayTexture ifNotNil: [ overlayTexture destroy ].
		overlayTexture := nil ].
	super destroy
]

{ #category : 'initialization' }
WebViewFormRenderer >> initialize [
	super initialize.
	overlayDirty := false.
	overlayCopyCount := 0
]

{ #category : 'accessing' }
WebViewFormRenderer >> overlayCopyCount [
	^ overlayCopyCount ifNil: [ 0 ]
]

{ #category : 'overlay' }
WebViewFormRenderer >> overlayForm: aForm bounds: aRectangle [
	"Called from the UI process (morph step). Store the overlay source buffer and its
	destination rectangle (texture coordinates); upload happens at present time under the mutex."
	mutex critical: [
		overlayForm := aForm.
		overlayBounds := aRectangle.
		overlayDirty := true ]
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
	mutex critical: [
		renderer copy: texture.
		self copyOverlay.
		renderer present ]
]

{ #category : 'overlay' }
WebViewFormRenderer >> validateOverlay [
	"Assumes mutex is held and renderer is valid. Creates/uploads the overlay texture as needed."
	overlayForm ifNil: [ ^ false ].
	(overlayTexture isNil or: [ overlayTexture isNull or: [ overlayExtent ~= overlayForm extent ] ]) ifTrue: [
		overlayTexture ifNotNil: [ overlayTexture destroy ].
		overlayTexture := renderer
			createTextureFormat: SDL_PIXELFORMAT_XRGB8888
			access: SDL_TEXTUREACCESS_STREAMING
			width: overlayForm width
			height: overlayForm height.
		overlayExtent := overlayForm extent.
		overlayDirty := true ].
	overlayDirty ifTrue: [
		overlayTexture updateTexturePixels: overlayForm bits pitch: overlayForm width * 4.
		overlayDirty := false ].
	^ true
]
