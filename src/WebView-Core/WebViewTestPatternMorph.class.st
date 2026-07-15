Class {
	#name : 'WebViewTestPatternMorph',
	#superclass : 'BorderedMorph',
	#instVars : [
		'phase',
		'buffer'
	],
	#category : 'WebView-Core',
	#package : 'WebView-Core'
}

{ #category : 'submorphs-add/remove' }
WebViewTestPatternMorph >> delete [
	self formRendererOrNil ifNotNil: [ :r | r removeOverlayFor: self ].
	super delete
]

{ #category : 'private' }
WebViewTestPatternMorph >> formRendererOrNil [
	| w r |
	w := self world ifNil: [ ^ nil ].
	r := w worldState worldRenderer osWindowRenderer.
	^ (r isKindOf: WebViewFormRenderer) ifTrue: [ r ] ifFalse: [ nil ]
]

{ #category : 'initialization' }
WebViewTestPatternMorph >> initialize [
	super initialize.
	phase := 0.
	buffer := Form extent: 320 @ 240 depth: 32.
	self extent: 320 @ 240.
	self color: (Color r: 0.1 g: 0.1 b: 0.15).
	self borderWidth: 2.
	self borderColor: Color orange
]

{ #category : 'initialization' }
WebViewTestPatternMorph >> intoWorld: aWorld [
	super intoWorld: aWorld.
	self startStepping
]

{ #category : 'private' }
WebViewTestPatternMorph >> pushOverlay [
	| formRenderer scale |
	formRenderer := self formRendererOrNil ifNil: [ ^ self ].
	scale := OSWorldRenderer canvasScaleFactor.
	formRenderer
		overlayFor: self
		pixels: buffer bits
		extent: buffer extent
		pitch: buffer width * 4
		bounds: ((self bounds origin * scale) rounded extent: (self extent * scale) rounded)
		dirtyRects: nil
]

{ #category : 'drawing' }
WebViewTestPatternMorph >> renderPattern [
	| canvas hue |
	canvas := buffer getCanvas.
	hue := phase * 360 / 320.
	canvas fillRectangle: (0 @ 0 extent: buffer extent) color: (Color h: hue s: 0.6 v: 0.5).
	canvas fillRectangle: (phase @ 40 extent: 60 @ 60) color: Color white.
	canvas fillRectangle: ((320 - phase) @ 140 extent: 60 @ 60) color: Color black.
	canvas drawString: 'M1 texture proof - GPU composited' at: 12 @ 12 font: nil color: Color white
]

{ #category : 'stepping' }
WebViewTestPatternMorph >> step [
	"Guarded: an error here must stop stepping and log, never open a debugger loop."
	[
	phase := (phase + 4) \\ 320.
	self renderPattern.
	self pushOverlay.
	self changed ]
		on: Error
		do: [ :e |
			self stopStepping.
			WebViewProjectPlan log: 'morph step ERROR (stepping stopped): ', e printString ]
]

{ #category : 'stepping' }
WebViewTestPatternMorph >> stepTime [
	^ 16
]

{ #category : 'stepping' }
WebViewTestPatternMorph >> wantsSteps [
	^ true
]
