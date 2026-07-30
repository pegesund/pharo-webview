"
A Bloc element that hosts a live cef_host browser -- the Bloc counterpart to the
Morphic WebViewCefMorph. Same shared-memory bridge underneath; the difference is
only the host widget toolkit.

WvBlocView is a BlElement whose background is the current browser frame, refreshed
from shared memory by a background 'live loop' that enqueues each blit onto the
space's UI thread. Mouse, keyboard and wheel events are forwarded to cef_host; the
element is resized-aware (tells cef_host to re-render at the new pixel size).

This class is self-contained (no product-specific dependencies) and works on both
macOS and Windows -- all platform differences live in WebViewCefMorph / WvPlatform.

Open one with:
	WvBlocView openOn: 'https://no.wikipedia.org/wiki/Lesing'.

Requires Bloc (loaded via the baseline's 'bloc' group).
"
Class {
	#name : 'WvBlocView',
	#superclass : 'BlElement',
	#instVars : [
		'wv',
		'live',
		'frameForm'
	],
	#category : 'WebView-Bloc',
	#package : 'WebView-Bloc'
}

{ #category : 'instance creation' }
WvBlocView class >> openOn: aUrl [
	"Open a native Bloc window showing aUrl in a live cef_host browser."
	| view space |
	view := self new.
	space := BlSpace new.
	space title: 'WebView (Bloc)'; extent: 1000 @ 720.
	space root addChild: view.
	view constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	space addEventHandlerOn: BlSpaceClosedEvent do: [ :e | [ view stop ] on: Error do: [ :x | ] ].
	space show.
	view startWithUrl: aUrl width: 1000 height: 680.
	^ view
]

{ #category : 'class initialization' }
WvBlocView class >> initialize [
	"Register for image startup so a snapshotted view never segfaults the VM (see
	 neutralizeSnapshottedInstances)."
	SessionManager default registerSystemClassNamed: self name
]

{ #category : 'session' }
WvBlocView class >> neutralizeSnapshottedInstances [
	"After an image restore every live WvBlocView holds a dead shm ExternalAddress
	 (external memory does not survive a snapshot). The resumed render loop would call
	 FFI on it and SEGFAULT the whole VM, so terminate the loop and drop the handles;
	 the view must be re-opened after resume anyway."
	self allInstances do: [ :el |
		[ (el instVarNamed: 'live') ifNotNil: [ :pr | pr terminate ] ] on: Error do: [ :e | ].
		[ el instVarNamed: 'live' put: nil ] on: Error do: [ :e | ].
		[ el instVarNamed: 'wv' put: nil ] on: Error do: [ :e | ].
		[ el space ifNotNil: [ :sp | sp close ] ] on: Error do: [ :e | ] ]
]

{ #category : 'session' }
WvBlocView class >> startUp: resuming [
	resuming ifTrue: [ [ self neutralizeSnapshottedInstances ] on: Error do: [ :e | ] ]
]

{ #category : 'initialization' }
WvBlocView >> initialize [
	super initialize.
	self background: (Color r: 0.1 g: 0.1 b: 0.12).
	self constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ]
]

{ #category : 'accessing' }
WvBlocView >> wv [
	"The underlying WebViewCefMorph (its shm bridge, launch/kill, command channel)."
	^ wv
]

{ #category : 'lifecycle' }
WvBlocView >> startWithUrl: aUrl width: w height: h [
	"Launch cef_host on aUrl, wire input + resize, and start the render loop."
	wv := WebViewCefMorph new.
	wv url: aUrl.
	wv extent: w @ h.
	wv launchHost.
	self attachInput.
	self attachResize.
	self startLiveLoop.
	^ self
]

{ #category : 'lifecycle' }
WvBlocView >> stop [
	"Terminate the render loop and kill the cef_host process + its temp files."
	live ifNotNil: [ [ live terminate ] on: Error do: [ :e | ] ]. live := nil.
	wv ifNotNil: [
		[ wv killHost ] on: Error do: [ :e | ].
		[ wv cleanupFiles ] on: Error do: [ :e | ] ]
]

{ #category : 'scripting' }
WvBlocView >> navigate: aUrl [
	wv ifNotNil: [ [ wv url: aUrl. wv writeCommand: { 'type' -> 'navigate'. 'url' -> aUrl } asDictionary ] on: Error do: [ :e | ] ]
]

{ #category : 'scripting' }
WvBlocView >> evalJs: aString [
	wv ifNotNil: [ [ wv evalJs: aString ] on: Error do: [ :e | ] ]
]

{ #category : 'rendering' }
WvBlocView >> refreshFrame [
	"Copy the current CEF frame from shared memory into a reused Form and show it as
	 the element background. safeFrameExtent gates the memcpy so a host that died
	 mid-write (garbage header) can never drive the copy past the mapping and crash."
	| shm ext w h |
	wv ifNil: [ ^ self ].
	[ wv ensureShm ] on: Error do: [ :e | ^ self ].
	shm := [ wv instVarNamed: 'shm' ] on: Error do: [ :e | nil ].
	shm ifNil: [ ^ self ].
	ext := [ shm safeFrameExtent ] on: Error do: [ :e | nil ].
	ext ifNil: [ ^ self ].
	w := ext x. h := ext y.
	(frameForm isNil or: [ frameForm extent ~= (w @ h) ]) ifTrue: [ frameForm := Form extent: w @ h depth: 32 ].
	LibC uniqueInstance memCopy: shm pixelsAddress to: frameForm bits size: (w * h * 4).
	"A fresh background object forces a repaint even though the Form is reused."
	self background: (BlImageBackground image: frameForm)
]

{ #category : 'rendering' }
WvBlocView >> startLiveLoop [
	"Background process: poll the shm seqlock; on each new frame enqueue a blit onto
	 the space's UI thread. Also pumps reverse events and drives debounced resize."
	live ifNotNil: [ [ live terminate ] on: Error do: [ :e | ] ].
	live := [
		| lastSeq |
		lastSeq := -1.
		[ self spaceStillOpen ] whileFalse: [ (Delay forMilliseconds: 60) wait ].
		[ self spaceStillOpen ] whileTrue: [
			| seq |
			[ wv ifNotNil: [ wv pumpEvents ] ] on: Error do: [ :e | ].
			[ self maybeSendResize ] on: Error do: [ :e | ].
			seq := lastSeq.
			[ (wv notNil and: [ wv ensureShm ]) ifTrue: [ seq := (wv instVarNamed: 'shm') seq ] ] on: Error do: [ :e | ].
			seq ~= lastSeq ifTrue: [
				lastSeq := seq.
				self space ifNotNil: [ :sp |
					sp enqueueTask: (BlTaskAction new action: [ [ self refreshFrame ] on: Error do: [ :e | ] ]) ] ].
			(Delay forMilliseconds: 50) wait ].
		live := nil ] fork.
	live priority: Processor userBackgroundPriority.
	live name: 'WvBlocView live'
]

{ #category : 'rendering' }
WvBlocView >> spaceStillOpen [
	"True while the element sits in an open space (a closed space can linger as
	 self space, so check isOpened too)."
	| sp |
	sp := self space.
	sp ifNil: [ ^ false ].
	^ [ sp isOpened ] on: Error do: [ :e | false ]
]

{ #category : 'geometry' }
WvBlocView >> browserExtent [
	^ (wv notNil and: [ [ wv browserExtent ] on: Error do: [ :e | nil ] ]) ifNil: [ 800 @ 600 ] ifNotNil: [ :x | x ]
]

{ #category : 'geometry' }
WvBlocView >> browserPointFor: aLocalPoint [
	"Bloc-local point -> browser pixel coords (the frame is scaled to the element)."
	| be ex |
	be := self browserExtent. ex := self extent.
	^ (((aLocalPoint x * be x / (ex x max: 1)) rounded) max: 0)
		@ (((aLocalPoint y * be y / (ex y max: 1)) rounded) max: 0)
]

{ #category : 'input' }
WvBlocView >> attachInput [
	"Forward mouse, wheel and keyboard events to cef_host via its command channel."
	self focusability: BlFocusability after.
	self addEventHandlerOn: BlMouseDownEvent do: [ :e | | p |
		p := self browserPointFor: e localPosition.
		self writeBrowser: { 'type' -> 'focus'. 'on' -> 1 }.
		self writeBrowser: { 'type' -> 'down'. 'x' -> p x. 'y' -> p y }.
		[ self requestFocus ] on: Error do: [ :x | ] ].
	self addEventHandlerOn: BlMouseUpEvent do: [ :e | | p |
		p := self browserPointFor: e localPosition.
		self writeBrowser: { 'type' -> 'up'. 'x' -> p x. 'y' -> p y } ].
	self addEventHandlerOn: BlMouseMoveEvent do: [ :e |
		e anyButtonPressed ifTrue: [ | p |
			p := self browserPointFor: e localPosition.
			self writeBrowser: { 'type' -> 'move'. 'buttons' -> 1. 'x' -> p x. 'y' -> p y } ] ].
	self addEventHandlerOn: BlMouseWheelEvent do: [ :e | | p dx dy step |
		p := self browserPointFor: e localPosition. step := 60. dx := 0. dy := 0.
		e isScrollUp ifTrue: [ dy := step ]. e isScrollDown ifTrue: [ dy := step negated ].
		e isScrollLeft ifTrue: [ dx := step ]. e isScrollRight ifTrue: [ dx := step negated ].
		(dx = 0 and: [ dy = 0 ]) ifFalse: [
			self writeBrowser: { 'type' -> 'scroll'. 'x' -> p x. 'y' -> p y. 'dx' -> dx. 'dy' -> dy } ] ].
	self addEventHandlerOn: BlKeyDownEvent do: [ :e | | code |
		code := self cefKeyCodeFor: e key.
		code ifNotNil: [ self writeBrowser: { 'type' -> 'key'. 'code' -> code } ].
		e key = KeyboardKey escape ifTrue: [ e consumed: true ] ].
	self addEventHandlerOn: BlTextInputEvent do: [ :e | | txt |
		txt := [ e text asString ] on: Error do: [ :x | '' ].
		txt isEmpty ifFalse: [ self writeBrowser: { 'type' -> 'key'. 'text' -> txt } ] ]
]

{ #category : 'input' }
WvBlocView >> cefKeyCodeFor: aKey [
	"CEF key code for a navigation/editing key, or nil for printable keys (those go
	 through BlTextInputEvent, so nothing is sent twice)."
	aKey ifNil: [ ^ nil ].
	(aKey = KeyboardKey enter or: [ aKey = KeyboardKey keypadEnter ]) ifTrue: [ ^ 13 ].
	aKey = KeyboardKey backspace ifTrue: [ ^ 8 ].
	aKey = KeyboardKey tab ifTrue: [ ^ 9 ].
	aKey = KeyboardKey escape ifTrue: [ ^ 27 ].
	aKey = KeyboardKey delete ifTrue: [ ^ 46 ].
	aKey = KeyboardKey left ifTrue: [ ^ 37 ].
	aKey = KeyboardKey up ifTrue: [ ^ 38 ].
	aKey = KeyboardKey right ifTrue: [ ^ 39 ].
	aKey = KeyboardKey down ifTrue: [ ^ 40 ].
	aKey = KeyboardKey pageUp ifTrue: [ ^ 33 ].
	aKey = KeyboardKey pageDown ifTrue: [ ^ 34 ].
	aKey = KeyboardKey home ifTrue: [ ^ 36 ].
	aKey = KeyboardKey end ifTrue: [ ^ 35 ].
	^ nil
]

{ #category : 'input' }
WvBlocView >> writeBrowser: aDict [
	wv ifNotNil: [ [ wv writeCommand: aDict asDictionary ] on: Error do: [ :e | ] ]
]

{ #category : 'geometry' }
WvBlocView >> attachResize [
	"On element resize, remember the wanted pixel size; the live loop debounces it and
	 tells cef_host to re-render at that size (so the frame is 1:1, not stretched)."
	self addEventHandlerOn: BlElementExtentChangedEvent do: [ :e |
		self userData at: #wantResize put: (self extent rounded max: 200 @ 200) ]
]

{ #category : 'geometry' }
WvBlocView >> maybeSendResize [
	"Called from the live loop: when the wanted size has been stable a few ticks and
	 differs from what cef_host renders, send ONE resize command (clamped to the shm
	 capacity 2560x1600)."
	| want stable shm cur w h |
	want := self userData at: #wantResize ifAbsent: [ ^ self ].
	(want = (self userData at: #lastWant ifAbsent: [ nil ]))
		ifTrue: [ stable := (self userData at: #wantStable ifAbsent: [ 0 ]) + 1 ]
		ifFalse: [ stable := 0 ].
	self userData at: #lastWant put: want.
	self userData at: #wantStable put: stable.
	stable < 4 ifTrue: [ ^ self ].
	self userData removeKey: #wantResize ifAbsent: [ ].
	wv ifNil: [ ^ self ].
	shm := [ wv instVarNamed: 'shm' ] on: Error do: [ :e | nil ].
	shm ifNil: [ ^ self ].
	cur := [ shm width @ shm height ] on: Error do: [ :e | ^ self ].
	w := ((want x rounded) max: 200) min: 2560.
	h := ((want y rounded) max: 200) min: 1600.
	(w @ h) = cur ifTrue: [ ^ self ].
	[ wv writeCommand: { 'type' -> 'resize'. 'w' -> w. 'h' -> h } asDictionary ] on: Error do: [ :e | ]
]
