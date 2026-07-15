Class {
	#name : 'WebViewCdpMorph',
	#superclass : 'BorderedMorph',
	#instVars : [
		'frameDir',
		'lastSeq',
		'currentForm',
		'helperPid',
		'url'
	],
	#category : 'WebView-Core',
	#package : 'WebView-Core'
}

{ #category : 'input' }
WebViewCdpMorph >> browserExtent [
	"The pixel size of the current browser frame (falls back to morph extent)."
	^ currentForm ifNotNil: [ :f | f extent ] ifNil: [ self extent ]
]

{ #category : 'submorphs-add/remove' }
WebViewCdpMorph >> delete [
	self formRendererOrNil ifNotNil: [ :r | r clearOverlay ].
	super delete
]

{ #category : 'drawing' }
WebViewCdpMorph >> drawOn: aCanvas [
	super drawOn: aCanvas.
	currentForm ifNil: [
		aCanvas drawString: 'WebViewCdpMorph - waiting for Chrome frames...' at: self topLeft + (8 @ 8) font: nil color: Color lightGreen ]
]

{ #category : 'private' }
WebViewCdpMorph >> formRendererOrNil [
	| w r |
	w := self world ifNil: [ ^ nil ].
	r := w worldState worldRenderer osWindowRenderer.
	^ (r isKindOf: WebViewFormRenderer) ifTrue: [ r ] ifFalse: [ nil ]
]

{ #category : 'accessing' }
WebViewCdpMorph >> frameDir: aString [
	frameDir := aString
]

{ #category : 'private' }
WebViewCdpMorph >> framePath [
	^ frameDir, '/frame.png'
]

{ #category : 'event handling' }
WebViewCdpMorph >> handlesKeyboard: anEvent [
	^ true
]

{ #category : 'event handling' }
WebViewCdpMorph >> handlesMouseDown: anEvent [
	^ true
]

{ #category : 'event handling' }
WebViewCdpMorph >> handlesMouseMove: anEvent [
	^ true
]

{ #category : 'event handling' }
WebViewCdpMorph >> handlesMouseOver: anEvent [
	^ true
]

{ #category : 'initialization' }
WebViewCdpMorph >> initialize [
	super initialize.
	frameDir := '/tmp/wv-cdp'.
	lastSeq := -1.
	url := 'https://example.com'.
	self extent: 800 @ 513.
	self color: (Color r: 0.05 g: 0.05 b: 0.08).
	self borderWidth: 1.
	self borderColor: Color green
]

{ #category : 'input' }
WebViewCdpMorph >> inputPath [
	^ frameDir, '/input.jsonl'
]

{ #category : 'stepping' }
WebViewCdpMorph >> intoWorld: aWorld [
	super intoWorld: aWorld.
	self comeToFront.
	self startStepping
]

{ #category : 'event handling' }
WebViewCdpMorph >> keyStroke: anEvent [
	| ch |
	ch := anEvent keyCharacter.
	ch ifNotNil: [
		self writeCommand: { 'type' -> 'key'. 'text' -> (String with: ch) } asDictionary ]
]

{ #category : 'frames' }
WebViewCdpMorph >> loadCurrentFrame [
	"Decode frame.png into a 32-bit Form. Returns the Form or nil on any error."
	^ [ ImageReadWriter formFromFileNamed: self framePath ]
		on: Error
		do: [ :e | WebViewProjectPlan log: 'CDP decode error: ', e messageText. nil ]
]

{ #category : 'event handling' }
WebViewCdpMorph >> mouseDown: anEvent [
	"A click on the morph -> forward to the browser as browser-pixel coords.
	NOTE: the overlay texture always draws ON TOP (v1 limitation), but Morphic
	hit-testing uses real z-order, so the morph is kept frontmost (see intoWorld:/
	comeToFront) - otherwise a window overlapping the morph would swallow clicks."
	| p |
	self comeToFront.
	p := self toBrowserCoords: anEvent position.
	self writeCommand: { 'type' -> 'click'. 'x' -> p x. 'y' -> p y } asDictionary.
	self takeKeyboardFocus
]

{ #category : 'event handling' }
WebViewCdpMorph >> mouseMove: anEvent [
	"Only stream moves while a button is held (drag), to avoid flooding the input
	channel on plain hover."
	anEvent anyButtonPressed ifFalse: [ ^ self ].
	self writeCommand: (self moveCommandFor: anEvent position)
]

{ #category : 'input' }
WebViewCdpMorph >> moveCommandFor: aWorldPoint [
	| p |
	p := self toBrowserCoords: aWorldPoint.
	^ { 'type' -> 'move'. 'x' -> p x. 'y' -> p y } asDictionary
]

{ #category : 'frames' }
WebViewCdpMorph >> pushForm: aForm [
	| r scale |
	r := self formRendererOrNil ifNil: [ ^ self ].
	scale := OSWorldRenderer canvasScaleFactor.
	r
		overlayForm: (aForm depth = 32 ifTrue: [ aForm ] ifFalse: [ aForm asFormOfDepth: 32 ])
		bounds: ((self bounds origin * scale) rounded extent: (self extent * scale) rounded)
]

{ #category : 'private' }
WebViewCdpMorph >> readSeq [

	| ref |
	ref := self seqPath asFileReference.
	ref exists ifFalse: [ ^ nil ].
	^ [ ref contents trimBoth asNumber ]
		  on: Error
		  do: [ :e | nil ]
]

{ #category : 'private' }
WebViewCdpMorph >> seqPath [
	^ frameDir, '/frame.seq'
]

{ #category : 'helper' }
WebViewCdpMorph >> startChromeHelper [
	"Spawn the node CDP helper for this morph url/dir. Requires OSSUnixSubprocess or
	falls back to a shell via LibC. Returns true if a spawn was attempted."
	| script cmd |
	script := '/Users/pegesund/dev/pharo-webview/cdp/chrome-screencast.mjs'.
	cmd := '/opt/homebrew/bin/node "', script, '" "', url, '" "', frameDir, '" 800 600 >> /tmp/wv-cdp-helper.log 2>&1 &'.
	LibC runCommand: cmd.
	^ true
]

{ #category : 'stepping' }
WebViewCdpMorph >> step [
	"Poll frame.seq; on change decode frame.png and push it as the overlay.
	Guarded: an error stops stepping and logs, never wedges the UI."
	[
	| seq form |
	seq := self readSeq.
	(seq notNil and: [ seq ~= lastSeq ]) ifTrue: [
		form := self loadCurrentFrame.
		form ifNotNil: [
			lastSeq := seq.
			currentForm := form.
			(self extent = form extent) ifFalse: [ self extent: form extent ].
			self pushForm: form.
			self changed ] ] ]
		on: Error
		do: [ :e |
			self stopStepping.
			WebViewProjectPlan log: 'WebViewCdpMorph step ERROR (stopped): ', e printString ]
]

{ #category : 'stepping' }
WebViewCdpMorph >> stepTime [
	^ 120
]

{ #category : 'input' }
WebViewCdpMorph >> toBrowserCoords: aPoint [
	"Map a WORLD point to browser pixel coordinates inside the frame."
	| local be me |
	local := aPoint - self topLeft.
	be := self browserExtent.
	me := self extent.
	^ (((local x * be x / (me x max: 1)) rounded) max: 0) @ (((local y * be y / (me y max: 1)) rounded) max: 0)
]

{ #category : 'accessing' }
WebViewCdpMorph >> url: aString [
	url := aString
]

{ #category : 'event handling' }
WebViewCdpMorph >> wantsKeyboardFocusFor: aSubmorph [
	^ true
]

{ #category : 'stepping' }
WebViewCdpMorph >> wantsSteps [
	^ true
]

{ #category : 'input' }
WebViewCdpMorph >> writeCommand: aDictionary [
	"Append one JSON command line to the input channel. Best-effort, never raises.
	Uses File>>openForAppend so a burst of events (keystrokes) is queued, not coalesced."
	[ | line stream |
	line := String streamContents: [ :s |
		s nextPut: ${.
		aDictionary keysAndValuesDo: [ :k :v |
			s nextPut: $"; nextPutAll: k; nextPutAll: '":'.
			(v isNumber) ifTrue: [ s nextPutAll: v printString ] ifFalse: [ s nextPut: $"; nextPutAll: v asString; nextPut: $" ].
			s nextPutAll: ',' ].
		s nextPutAll: '"_":0}' ].
	stream := (File named: self inputPath) openForAppend.
	[ stream nextPutAll: line asByteArray; nextPut: Character lf asInteger ] ensure: [ stream close ] ]
		on: Error do: [ :e | WebViewProjectPlan log: 'writeCommand error: ', e messageText ]
]
