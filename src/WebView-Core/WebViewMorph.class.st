Class {
	#name : 'WebViewMorph',
	#superclass : 'BorderedMorph',
	#instVars : [
		'shim'
	],
	#category : 'WebView-Core',
	#package : 'WebView-Core'
}

{ #category : 'submorphs-add/remove' }
WebViewMorph >> delete [
	self formRendererOrNil ifNotNil: [ :r | r clearOverlay ].
	shim ifNotNil: [ shim destroy. shim := nil ].
	super delete
]

{ #category : 'drawing' }
WebViewMorph >> drawOn: aCanvas [
	super drawOn: aCanvas.
	aCanvas drawString: 'WebViewMorph (engine frame composites on top)' at: self topLeft + (8 @ 8) font: nil color: Color lightGray
]

{ #category : 'private' }
WebViewMorph >> formRendererOrNil [
	| w r |
	w := self world ifNil: [ ^ nil ].
	r := w worldState worldRenderer osWindowRenderer.
	^ (r isKindOf: WebViewFormRenderer) ifTrue: [ r ] ifFalse: [ nil ]
]

{ #category : 'initialization' }
WebViewMorph >> initialize [
	super initialize.
	self extent: 480 @ 360.
	self color: (Color r: 0.05 g: 0.05 b: 0.08).
	self borderWidth: 1.
	self borderColor: Color gray
]

{ #category : 'initialization' }
WebViewMorph >> intoWorld: aWorld [
	super intoWorld: aWorld.
	shim ifNil: [
		shim := WvShim new.
		shim openExtent: self extent ].
	self startStepping
]

{ #category : 'private' }
WebViewMorph >> pushFrame [
	| r scale |
	r := self formRendererOrNil ifNil: [ ^ self ].
	scale := OSWorldRenderer canvasScaleFactor.
	r
		overlayPixels: shim frameBuffer
		extent: shim frameWidth @ shim frameHeight
		pitch: shim frameWidth * 4
		bounds: ((self bounds origin * scale) rounded extent: (self extent * scale) rounded)
		dirtyRects: shim dirtyRects
]

{ #category : 'accessing' }
WebViewMorph >> shim [
	^ shim
]

{ #category : 'stepping' }
WebViewMorph >> step [
	"Poll the shim for a new engine frame; on error stop stepping and log -
	never let an error loop wedge the UI."
	[
	shim ifNil: [ ^ self ].
	shim tick.
	shim frameReady ifTrue: [
		self pushFrame.
		shim frameAck.
		self changed ] ]
		on: Error
		do: [ :e |
			self stopStepping.
			WebViewProjectPlan log: 'WebViewMorph step ERROR (stepping stopped): ', e printString ]
]

{ #category : 'stepping' }
WebViewMorph >> stepTime [
	^ 33
]

{ #category : 'stepping' }
WebViewMorph >> wantsSteps [
	^ true
]
