Class {
	#name : 'WebViewCefMorph',
	#superclass : 'BorderedMorph',
	#instVars : [
		'shm',
		'lastSeq',
		'url',
		'shmPath',
		'inputPath',
		'hostPid'
	],
	#category : 'WebView-Core',
	#package : 'WebView-Core'
}

{ #category : 'input' }
WebViewCefMorph >> browserExtent [
	^ (shm notNil and: [ shm isValid ]) ifTrue: [ shm width @ shm height ] ifFalse: [ self extent ]
]

{ #category : 'submorphs-add/remove' }
WebViewCefMorph >> delete [
	self formRendererOrNil ifNotNil: [ :r | r clearOverlay ].
	shm ifNotNil: [ shm close. shm := nil ].
	super delete
]

{ #category : 'drawing' }
WebViewCefMorph >> drawOn: aCanvas [
	super drawOn: aCanvas.
	lastSeq < 0 ifTrue: [
		aCanvas drawString: 'WebViewCefMorph - waiting for CEF frames...' at: self topLeft + (8@8) font: nil color: Color cyan ]
]

{ #category : 'private' }
WebViewCefMorph >> ensureShm [
	(shm notNil and: [ shm isValid ]) ifTrue: [ ^ true ].
	shm := WvSharedMemory openPath: shmPath maxWidth: 800 maxHeight: 600.
	^ shm notNil and: [ shm isValid ]
]

{ #category : 'private' }
WebViewCefMorph >> formRendererOrNil [
	| w r |
	w := self world ifNil: [ ^ nil ].
	r := w worldState worldRenderer osWindowRenderer.
	^ (r isKindOf: WebViewFormRenderer) ifTrue: [ r ] ifFalse: [ nil ]
]

{ #category : 'event handling' }
WebViewCefMorph >> handlesKeyboard: anEvent [ ^ true
]

{ #category : 'event handling' }
WebViewCefMorph >> handlesMouseDown: anEvent [ ^ true
]

{ #category : 'event handling' }
WebViewCefMorph >> handlesMouseMove: anEvent [ ^ true
]

{ #category : 'initialization' }
WebViewCefMorph >> initialize [
	super initialize.
	lastSeq := -1.
	url := 'https://example.com'.
	shmPath := '/tmp/wv-cef.shm'.
	inputPath := '/tmp/wv-cef.input'.
	self extent: 800 @ 600.
	self color: (Color r: 0.1 g: 0.1 b: 0.12).
	self borderWidth: 1.
	self borderColor: Color cyan
]

{ #category : 'stepping' }
WebViewCefMorph >> intoWorld: aWorld [
	super intoWorld: aWorld.
	self comeToFront.
	self startStepping
]

{ #category : 'event handling' }
WebViewCefMorph >> keyStroke: anEvent [
	| ch |
	ch := anEvent keyCharacter.
	ch ifNotNil: [ self writeCommand: { 'type' -> 'key'. 'text' -> (String with: ch) } asDictionary ]
]

{ #category : 'event handling' }
WebViewCefMorph >> mouseDown: anEvent [
	| p |
	self comeToFront.
	p := self toBrowserCoords: anEvent position.
	self writeCommand: { 'type' -> 'click'. 'x' -> p x. 'y' -> p y } asDictionary.
	self takeKeyboardFocus
]

{ #category : 'event handling' }
WebViewCefMorph >> mouseMove: anEvent [
	| p |
	anEvent anyButtonPressed ifFalse: [ ^ self ].
	p := self toBrowserCoords: anEvent position.
	self writeCommand: { 'type' -> 'move'. 'x' -> p x. 'y' -> p y } asDictionary
]

{ #category : 'frames' }
WebViewCefMorph >> pushFrame [
	| r scale |
	r := self formRendererOrNil ifNil: [ ^ self ].
	scale := OSWorldRenderer canvasScaleFactor.
	r
		overlayPixels: shm pixelsAddress
		extent: shm width @ shm height
		pitch: shm width * 4
		bounds: ((self bounds origin * scale) rounded extent: (self extent * scale) rounded)
		dirtyRects: nil
]

{ #category : 'accessing' }
WebViewCefMorph >> shmPath: aString [ ^ shmPath := aString
]

{ #category : 'stepping' }
WebViewCefMorph >> step [
	[
	self ensureShm ifFalse: [ ^ self ].
	shm alive ifFalse: [ ^ self ].
	shm seq = lastSeq ifTrue: [ ^ self ].
	lastSeq := shm seq.
	(self extent = (shm width @ shm height)) ifFalse: [ self extent: shm width @ shm height ].
	self pushFrame.
	self changed ]
		on: Error
		do: [ :e | self stopStepping. WebViewProjectPlan log: 'CefMorph step ERROR: ', e printString ]
]

{ #category : 'stepping' }
WebViewCefMorph >> stepTime [ ^ 16
]

{ #category : 'input' }
WebViewCefMorph >> toBrowserCoords: aWorldPoint [
	| local be me |
	local := aWorldPoint - self topLeft.
	be := self browserExtent.
	me := self extent.
	^ (((local x * be x / (me x max: 1)) rounded) max: 0) @ (((local y * be y / (me y max: 1)) rounded) max: 0)
]

{ #category : 'accessing' }
WebViewCefMorph >> url: aString [ ^ url := aString
]

{ #category : 'event handling' }
WebViewCefMorph >> wantsKeyboardFocusFor: aSubmorph [ ^ true
]

{ #category : 'stepping' }
WebViewCefMorph >> wantsSteps [ ^ true
]

{ #category : 'input' }
WebViewCefMorph >> writeCommand: aDictionary [
	"Append one JSON command line to the CEF host input channel."
	[ | line stream |
	line := String streamContents: [ :s |
		s nextPut: ${.
		aDictionary keysAndValuesDo: [ :k :v |
			s nextPut: $"; nextPutAll: k; nextPutAll: '":'.
			v isNumber ifTrue: [ s nextPutAll: v printString ] ifFalse: [ s nextPut: $"; nextPutAll: v asString; nextPut: $" ].
			s nextPutAll: ',' ].
		s nextPutAll: '"_":0}' ].
	stream := (File named: inputPath) openForAppend.
	[ stream nextPutAll: line asByteArray; nextPut: Character lf asInteger ] ensure: [ stream close ] ]
		on: Error do: [ :e | WebViewProjectPlan log: 'CefMorph writeCommand error: ', e messageText ]
]
