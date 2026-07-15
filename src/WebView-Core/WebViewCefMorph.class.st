Class {
	#name : 'WebViewCefMorph',
	#superclass : 'BorderedMorph',
	#instVars : [
		'shm',
		'lastSeq',
		'url',
		'shmPath',
		'inputPath',
		'pidPath',
		'id',
		'ownsHost'
	],
	#category : 'WebView-Core',
	#package : 'WebView-Core'
}

{ #category : 'config' }
WebViewCefMorph class >> binaryPath [
	"The cef_host executable. Resolution order: WV_CEF_HOST env var, then a
	value set via binaryPath:, then the built-in default."

	| env |
	env := [ OSPlatform current environment at: 'WV_CEF_HOST' ifAbsent: [ nil ] ]
		       on: Error
		       do: [ :e | nil ].
	env ifNotNil: [ ^ env ].
	^ Smalltalk at: #WvCefHostPath ifAbsent: [ self defaultBinaryPath ]
]

{ #category : 'config' }
WebViewCefMorph class >> binaryPath: aString [
	Smalltalk at: #WvCefHostPath put: aString
]

{ #category : 'config' }
WebViewCefMorph class >> defaultBinaryPath [
	^ '/Users/pegesund/dev/pharo-webview/cef_host/build/cef_host.app/Contents/MacOS/cef_host'
]

{ #category : 'config' }
WebViewCefMorph class >> nextId [
	| n |
	n := (Smalltalk at: #WvCefIdCounter ifAbsent: [ 0 ]) + 1.
	Smalltalk at: #WvCefIdCounter put: n.
	^ n
]

{ #category : 'input' }
WebViewCefMorph >> browserExtent [
	^ (shm notNil and: [ shm isValid ]) ifTrue: [ shm width @ shm height ] ifFalse: [ self extent ]
]

{ #category : 'lifecycle' }
WebViewCefMorph >> cleanupFiles [
	#('.shm' '.shm.cache' '.input' '.input.status' '.pid') do: [ :suffix |
		[ ('/tmp/wv-cef-', id printString, suffix) asFileReference ensureDelete ] on: Error do: [:e|] ]
]

{ #category : 'submorphs-add/remove' }
WebViewCefMorph >> delete [
	self stopStepping.
	self formRendererOrNil ifNotNil: [ :r | r removeOverlayFor: self ].
	shm ifNotNil: [ shm close. shm := nil ].
	self killHost.
	self cleanupFiles.
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
	shm ifNotNil: [ shm close. shm := nil ].
	shmPath asFileReference exists ifFalse: [ ^ false ].
	shm := WvSharedMemory openPath: shmPath.
	^ shm notNil and: [ shm isValid ]
]

{ #category : 'event handling' }
WebViewCefMorph >> focusChanged: aBoolean [
	"Tell CEF whether this webview has keyboard focus."
	self writeCommand: { 'type' -> 'focus'. 'on' -> (aBoolean ifTrue: [1] ifFalse: [0]) } asDictionary
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

{ #category : 'visibility' }
WebViewCefMorph >> hide [
	self visible: false.
	self formRendererOrNil ifNotNil: [ :r | r removeOverlayFor: self ]
]

{ #category : 'initialization' }
WebViewCefMorph >> initialize [
	super initialize.
	lastSeq := -1.
	url := 'https://example.com'.
	ownsHost := false.
	id := WebViewCefMorph nextId.
	shmPath := '/tmp/wv-cef-', id printString, '.shm'.
	inputPath := '/tmp/wv-cef-', id printString, '.input'.
	pidPath := '/tmp/wv-cef-', id printString, '.pid'.
	self extent: 800 @ 600.
	self color: (Color r: 0.1 g: 0.1 b: 0.12).
	self borderWidth: 1.
	self borderColor: Color cyan
]

{ #category : 'accessing' }
WebViewCefMorph >> inputPath [ ^ inputPath
]

{ #category : 'stepping' }
WebViewCefMorph >> intoWorld: aWorld [
	super intoWorld: aWorld.
	self launchHost.
	self comeToFront.
	self startStepping
]

{ #category : 'event handling' }
WebViewCefMorph >> keyStroke: anEvent [
	"Route keystrokes to CEF. Printable chars go as text; control/navigation keys
	go with a Windows virtual key code so CEF handles them (backspace, enter, arrows...)."
	| kv ch code |
	kv := anEvent keyValue.
	ch := anEvent keyCharacter.
	code := 0.
	kv = 8 ifTrue: [ code := 8 ].
	kv = 9 ifTrue: [ code := 9 ].
	(kv = 13 or: [ kv = 3 ]) ifTrue: [ code := 13 ].
	kv = 27 ifTrue: [ code := 27 ].
	kv = 127 ifTrue: [ code := 46 ].
	kv = 28 ifTrue: [ code := 37 ].
	kv = 29 ifTrue: [ code := 39 ].
	kv = 30 ifTrue: [ code := 38 ].
	kv = 31 ifTrue: [ code := 40 ].
	code ~= 0
		ifTrue: [ self writeCommand: { 'type' -> 'key'. 'code' -> code } asDictionary ]
		ifFalse: [ (ch notNil and: [ ch asInteger between: 32 and: 126 ])
			ifTrue: [ self writeCommand: { 'type' -> 'key'. 'text' -> (String with: ch) } asDictionary ] ]
]

{ #category : 'event handling' }
WebViewCefMorph >> keyboardFocusChange: aBoolean [
	super keyboardFocusChange: aBoolean.
	ownsHost == true ifTrue: [ self focusChanged: aBoolean ]
]

{ #category : 'lifecycle' }
WebViewCefMorph >> killHost [

	| pid |
	ownsHost ifFalse: [ ^ self ].
	pid := [
		       pidPath asFileReference exists
			       ifTrue: [ pidPath asFileReference contents trimBoth ]
			       ifFalse: [ nil ] ]
		       on: Error
		       do: [ :e | nil ].
	(pid notNil and: [ pid notEmpty ]) ifTrue: [ LibC runCommand: 'kill ' , pid , ' 2>/dev/null' ].
	ownsHost := false
]

{ #category : 'lifecycle' }
WebViewCefMorph >> launchHost [
	| cmd scale w h |
	ownsHost ifTrue: [ ^ self ].
	ownsHost := true.
	self cleanupFiles.
	scale := OSWorldRenderer canvasScaleFactor.
	w := ((self width * scale) rounded max: 200) min: 2560.
	h := ((self height * scale) rounded max: 200) min: 1600.
	cmd := '"', WebViewCefMorph binaryPath, '" "', url, '" ', w printString, ' ', h printString, ' "', shmPath, '" "', inputPath, '" >/tmp/wv-cef-', id printString, '.log 2>&1 & echo $! > "', pidPath, '"'.
	LibC runCommand: cmd.
	WebViewProjectPlan log: 'launched cef_host #', id printString, ' at ', w printString, 'x', h printString
]

{ #category : 'geometry' }
WebViewCefMorph >> maybeResize [
	"Send a resize only when the target browser-pixel size actually changes (debounced
	via a per-id last-sent cache), and never for tiny transient sizes."
	| scale dw dh target sent |
	(shm notNil and: [ shm isValid ]) ifFalse: [ ^ self ].
	scale := OSWorldRenderer canvasScaleFactor.
	dw := (self width * scale) rounded.
	dh := (self height * scale) rounded.
	(dw < 50 or: [ dh < 50 ]) ifTrue: [ ^ self ].
	target := dw @ dh.
	(target = (shm width @ shm height)) ifTrue: [ ^ self ].
	sent := (Smalltalk at: #WvResizeSent ifAbsentPut: [ IdentityDictionary new ]) at: id ifAbsent: [ nil ].
	target = sent ifTrue: [ ^ self ].
	(Smalltalk at: #WvResizeSent) at: id put: target.
	self writeCommand: { 'type' -> 'resize'. 'w' -> dw. 'h' -> dh } asDictionary
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
		overlayFor: self
		pixels: shm pixelsAddress
		extent: shm width @ shm height
		pitch: shm width * 4
		bounds: ((self bounds origin * scale) rounded extent: (self extent * scale) rounded)
		dirtyRects: nil
]

{ #category : 'frames' }
WebViewCefMorph >> pushFrameDirty: useDirty [
	| r scale rects |
	r := self formRendererOrNil ifNil: [ ^ self ].
	scale := OSWorldRenderer canvasScaleFactor.
	rects := useDirty ifTrue: [ shm dirtyRects ] ifFalse: [ nil ].
	r
		overlayFor: self
		pixels: shm pixelsAddress
		extent: shm width @ shm height
		pitch: shm width * 4
		bounds: ((self bounds origin * scale) rounded extent: (self extent * scale) rounded)
		dirtyRects: rects
]

{ #category : 'geometry' }
WebViewCefMorph >> sendResize [
	| scale w h |
	scale := OSWorldRenderer canvasScaleFactor.
	w := (self width * scale) rounded max: 1.
	h := (self height * scale) rounded max: 1.
	self writeCommand: { 'type' -> 'resize'. 'w' -> w. 'h' -> h } asDictionary
]

{ #category : 'accessing' }
WebViewCefMorph >> shmPath: aString [ ^ shmPath := aString
]

{ #category : 'visibility' }
WebViewCefMorph >> show [
	self visible: true.
	lastSeq := -1
]

{ #category : 'accessing' }
WebViewCefMorph >> statusPath [ ^ inputPath, '.status'
]

{ #category : 'stepping' }
WebViewCefMorph >> step [
	[ | seq noSkip |
	self visible ifFalse: [
		self formRendererOrNil ifNotNil: [ :r | r removeOverlayFor: self ].
		^ self ].
	self ensureShm ifFalse: [ ^ self ].
	shm alive ifFalse: [ ^ self ].
	self maybeResize.
	seq := shm seq.
	seq = lastSeq ifTrue: [ ^ self ].
	noSkip := seq = (lastSeq + 1).
	lastSeq := seq.
	self pushFrameDirty: noSkip.
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
