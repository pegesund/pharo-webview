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
WebViewCefMorph class >> cacheDir [
	"Persistent CEF cache/cookie root (macOS). Survives restarts so cookie-consent sticks."
	^ FileLocator home / 'Library' / 'Application Support' / 'pharo-webview' / 'cache'
]

{ #category : 'config' }
WebViewCefMorph class >> claimCacheSlot [
	"Lowest slot index not held by a currently-live browser. A lone browser reuses slot 0
	 across sessions, so its persistent cookie cache is reused and consent banners stop."
	| used i |
	used := ((self allInstances
		select: [ :m | m world notNil and: [ (m valueOfProperty: #wvCacheSlot ifAbsent: [ nil ]) notNil ] ])
		collect: [ :m | m valueOfProperty: #wvCacheSlot ]) asSet.
	i := 0.
	[ used includes: i ] whileTrue: [ i := i + 1 ].
	^ i
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

{ #category : 'screenshot' }
WebViewCefMorph >> asForm [
	"A Pharo Form snapshot of the current browser frame, read from shared memory."
	| w h form bits po |
	(shm isNil or: [ shm isValid not ]) ifTrue: [ ^ nil ].
	w := shm width. h := shm height.
	(w > 0 and: [ h > 0 ]) ifFalse: [ ^ nil ].
	form := Form extent: w @ h depth: 32.
	bits := form bits.
	po := shm pixelsOffset.
	1 to: w * h do: [ :i |
		bits at: i put: ((shm u32At: (po + ((i - 1) * 4))) bitOr: 16rFF000000) ].
	^ form
]

{ #category : 'input' }
WebViewCefMorph >> browserExtent [
	^ (shm notNil and: [ shm isValid ]) ifTrue: [ shm width @ shm height ] ifFalse: [ self extent ]
]

{ #category : 'lifecycle' }
WebViewCefMorph >> cachePath [
	"Persistent per-slot cache dir, claimed once per host launch."
	| slot dir |
	slot := self valueOfProperty: #wvCacheSlot ifAbsent: [ nil ].
	slot isNil ifTrue: [ slot := WebViewCefMorph claimCacheSlot. self setProperty: #wvCacheSlot toValue: slot ].
	dir := WebViewCefMorph cacheDir / ('slot-', slot printString).
	[ dir ensureCreateDirectory ] on: Error do: [ :e | ].
	^ dir fullName
]

{ #category : 'lifecycle' }
WebViewCefMorph >> cleanupFiles [
	#('.shm' '.shm.cache' '.input' '.input.status' '.input.events' '.pid') do: [ :suffix |
		[ ('/tmp/wv-cef-', id printString, suffix) asFileReference ensureDelete ] on: Error do: [:e|] ].
	self setProperty: #wvEventsOffset toValue: 0
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

{ #category : 'events' }
WebViewCefMorph >> dispatchEventLine: aString [
	| evt name |
	evt := [ STONJSON fromString: aString ] on: Error do: [ :e | nil ].
	(evt isNil or: [ (evt isKindOf: Dictionary) not ]) ifTrue: [ ^ self ].
	name := evt at: 'event' ifAbsent: [ nil ].
	name ifNil: [ ^ self ].
	name = 'js' ifTrue: [ | jn |
		jn := evt at: 'name' ifAbsent: [ nil ].
		jn = '__eval' ifTrue: [ ^ self handleEvalResult: (evt at: 'data' ifAbsent: [ nil ]) ].
		self fireCallbacks: #js with: evt.
		jn ifNotNil: [ self fireCallbacks: ('js:', jn) asSymbol with: evt ].
		^ self ].
	self fireCallbacks: name asSymbol with: evt
]

{ #category : 'drawing' }
WebViewCefMorph >> drawOn: aCanvas [
	"The live CEF texture is composited over us by WebViewFormRenderer (occlusion-
	clipped to real z-order). We only draw an opaque backing so the browser area is
	part of the world Form and morphs in front occlude it correctly."
	aCanvas fillRectangle: self bounds color: Color white
]

{ #category : 'scripting' }
WebViewCefMorph >> ensureLoadCounter [
	"Install (once) an internal loadEnd callback that bumps #wvLoadCount, so
	automation can wait for the NEXT navigation to complete."
	(self hasProperty: #wvLoadCounterInstalled) ifTrue: [ ^ self ].
	self setProperty: #wvLoadCounterInstalled toValue: true.
	self onEvent: #loadEnd do: [ :e |
		self setProperty: #wvLoadCount toValue: (self loadCount + 1) ]
]

{ #category : 'private' }
WebViewCefMorph >> ensureShm [
	(shm notNil and: [ shm isValid ]) ifTrue: [ ^ true ].
	shm ifNotNil: [ shm close. shm := nil ].
	shmPath asFileReference exists ifFalse: [ ^ false ].
	shm := WvSharedMemory openPath: shmPath.
	^ shm notNil and: [ shm isValid ]
]

{ #category : 'scripting' }
WebViewCefMorph >> evalJs: jsString [
	"Run arbitrary JavaScript in the page (DOM manipulation, fire-and-forget)."
	self writeCommand: { 'type' -> 'eval'. 'js' -> jsString } asDictionary
]

{ #category : 'scripting' }
WebViewCefMorph >> evalJs: jsString then: aBlock [
	"Run a JS EXPRESSION and deliver its (JSON-able) value to aBlock on the UI
	process. For multiple statements, pass a function expression, e.g.
	'(function(){ ...; return x })()'. On a JS exception the error is logged."
	| reqId wrapped cbs |
	reqId := self nextEvalId.
	cbs := self valueOfProperty: #wvEvalCallbacks ifAbsent: [ nil ].
	cbs ifNil: [ cbs := Dictionary new. self setProperty: #wvEvalCallbacks toValue: cbs ].
	cbs at: reqId put: aBlock.
	wrapped := String streamContents: [ :s |
		s nextPutAll: '(function(){try{var r=('; nextPutAll: jsString; nextPut: Character lf; nextPutAll: ');'.
		s nextPutAll: 'window.pharo.emit("__eval",{id:'; nextPutAll: reqId printString; nextPutAll: ',ok:true,value:r});'.
		s nextPutAll: '}catch(e){window.pharo.emit("__eval",{id:'; nextPutAll: reqId printString.
		s nextPutAll: ',ok:false,error:String((e&&e.message)||e)});}})();' ].
	self evalJs: wrapped
]

{ #category : 'scripting' }
WebViewCefMorph >> evalJsSync: jsString [
	"Run a JS expression and BLOCK the calling process until its value returns.
	MUST be called from a background process (never the UI process), or the UI
	step that delivers the result can't run. Returns nil on timeout."

	| sem result done |
	sem := Semaphore new.
	done := false.
	self evalJs: jsString then: [ :r |
			result := r.
			done := true.
			sem signal ].
	sem waitTimeoutMilliseconds: (self valueOfProperty: #wvSyncTimeoutMs ifAbsent: [ 10000 ]).
	done ifFalse: [
			WebViewProjectPlan log: 'evalJsSync timeout: ' , (jsString truncateTo: 60).
			^ nil ].
	^ result
]

{ #category : 'events' }
WebViewCefMorph >> eventsPath [
	^ inputPath, '.events'
]

{ #category : 'events' }
WebViewCefMorph >> fireCallbacks: aSymbol with: evt [
	| cbs |
	cbs := self valueOfProperty: #wvCallbacks ifAbsent: [ ^ self ].
	(cbs at: aSymbol ifAbsent: [ nil ]) ifNotNil: [ :blocks |
		blocks copy do: [ :blk |
			[ blk cull: evt ]
				on: Error
				do: [ :e | WebViewProjectPlan log: 'wv callback error: ', e printString ] ] ]
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

{ #category : 'scripting' }
WebViewCefMorph >> handleEvalResult: data [
	| id blk cbs |
	(data isKindOf: Dictionary) ifFalse: [ ^ self ].
	id := data at: 'id' ifAbsent: [ nil ].
	cbs := self valueOfProperty: #wvEvalCallbacks ifAbsent: [ nil ].
	(cbs isNil or: [ id isNil ]) ifTrue: [ ^ self ].
	blk := cbs removeKey: id ifAbsent: [ nil ].
	blk ifNil: [ ^ self ].
	(data at: 'ok' ifAbsent: [ false ])
		ifTrue: [ [ blk cull: (data at: 'value' ifAbsent: [ nil ]) ]
			on: Error do: [ :e | WebViewProjectPlan log: 'evalJs then-block error: ', e printString ] ]
		ifFalse: [ WebViewProjectPlan log: 'evalJs JS error: ', (data at: 'error' ifAbsent: [ '?' ]) printString ]
]

{ #category : 'event handling' }
WebViewCefMorph >> handlesKeyDown: anEvent [ ^ true
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

{ #category : 'event handling' }
WebViewCefMorph >> handlesMouseWheel: anEvent [ ^ true
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

{ #category : 'private' }
WebViewCefMorph >> jsonStringOn: aStream put: aString [
	"Write aString as a properly-escaped JSON string literal (with quotes)."
	aStream nextPut: $".
	aString do: [ :c | | code |
		code := c asInteger.
		code = 34 ifTrue: [ aStream nextPutAll: '\"' ] ifFalse: [
		code = 92 ifTrue: [ aStream nextPutAll: '\\' ] ifFalse: [
		code = 10 ifTrue: [ aStream nextPutAll: '\n' ] ifFalse: [
		code = 13 ifTrue: [ aStream nextPutAll: '\r' ] ifFalse: [
		code = 9 ifTrue: [ aStream nextPutAll: '\t' ] ifFalse: [
		code = 8 ifTrue: [ aStream nextPutAll: '\b' ] ifFalse: [
		code = 12 ifTrue: [ aStream nextPutAll: '\f' ] ifFalse: [
		code < 32 ifTrue: [ | hex | hex := code printString: 16.
			aStream nextPutAll: '\u00'. hex size < 2 ifTrue: [ aStream nextPut: $0 ]. aStream nextPutAll: hex ]
		ifFalse: [ aStream nextPut: c ] ] ] ] ] ] ] ] ].
	aStream nextPut: $"
]

{ #category : 'events' }
WebViewCefMorph >> keyDown: anEvent [
	"Navigation keys (arrows, page up/down, home, end) AND, on macOS/SDL, editing keys
	 (backspace, tab, enter, escape, delete) + non-ASCII printable chars (æøå) arrive here
	 rather than in keyStroke:. Forward them, recording what was sent so a following
	 keyStroke: (platforms where both fire) can dedupe instead of double-sending."
	self withErrorLog: [
		| kv code ch cv |
		kv := anEvent keyValue.
		code := 0.
		kv = 30 ifTrue: [ code := 38 ]. kv = 31 ifTrue: [ code := 40 ].
		kv = 28 ifTrue: [ code := 37 ]. kv = 29 ifTrue: [ code := 39 ].
		kv = 11 ifTrue: [ code := 33 ]. kv = 12 ifTrue: [ code := 34 ].
		kv = 1 ifTrue: [ code := 36 ]. kv = 4 ifTrue: [ code := 35 ].
		kv = 8 ifTrue: [ code := 8 ]. kv = 9 ifTrue: [ code := 9 ].
		(kv = 13 or: [ kv = 3 ]) ifTrue: [ code := 13 ].
		kv = 27 ifTrue: [ code := 27 ]. kv = 127 ifTrue: [ code := 46 ].
		code ~= 0
			ifTrue: [
				self setProperty: #leseKeyDownCode toValue: code.
				self writeCommand: { 'type' -> 'key'. 'code' -> code } asDictionary ]
			ifFalse: [
				ch := anEvent keyCharacter.
				ch ifNotNil: [
					cv := ch asInteger.
					(cv >= 128 and: [ cv < 65535 ]) ifTrue: [
						self setProperty: #leseKeyDownText toValue: cv.
						self writeCommand: { 'type' -> 'key'. 'text' -> (String with: ch) } asDictionary ] ] ] ]
		label: 'keyDown'
]

{ #category : 'events' }
WebViewCefMorph >> keyStroke: anEvent [
	"Editing keys + printable text. ASCII always goes here. Editing keys and non-ASCII
	 (æøå) normally arrive via keyDown: on macOS; on platforms where they also reach
	 keyStroke: we dedupe against what keyDown: recorded so nothing is sent twice."
	self withErrorLog: [
		| ch cv code |
		ch := anEvent keyCharacter ifNil: [ ^ self ].
		cv := ch asInteger.
		code := 0.
		cv = 8 ifTrue: [ code := 8 ]. cv = 9 ifTrue: [ code := 9 ].
		(cv = 13 or: [ cv = 10 or: [ cv = 3 ] ]) ifTrue: [ code := 13 ].
		cv = 27 ifTrue: [ code := 27 ]. cv = 127 ifTrue: [ code := 46 ].
		code ~= 0
			ifTrue: [
				(self valueOfProperty: #leseKeyDownCode ifAbsent: [ nil ]) = code
					ifTrue: [ self setProperty: #leseKeyDownCode toValue: nil ]
					ifFalse: [ self writeCommand: { 'type' -> 'key'. 'code' -> code } asDictionary ] ]
			ifFalse: [
				(cv between: 32 and: 126)
					ifTrue: [ self writeCommand: { 'type' -> 'key'. 'text' -> (String with: ch) } asDictionary ]
					ifFalse: [ (cv >= 128 and: [ cv < 65535 ]) ifTrue: [
						(self valueOfProperty: #leseKeyDownText ifAbsent: [ nil ]) = cv
							ifTrue: [ self setProperty: #leseKeyDownText toValue: nil ]
							ifFalse: [ self writeCommand: { 'type' -> 'key'. 'text' -> (String with: ch) } asDictionary ] ] ] ] ]
		label: 'keyStroke'
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
	"Launch cef_host through a perl wrapper that CLOSES all inherited file
	 descriptors >= 3 before exec. Otherwise the child (via LibC runCommand -> sh)
	 inherits every open fd of the image, INCLUDING any server listen/accept socket
	 (e.g. the SisServer/MCP port). A long-lived cef_host then keeps that socket
	 alive -- wedging the live server if it grabs an active connection, and holding
	 the port after the image exits so the next boot fails with 'Address already in
	 use'. Closing 3..1023 first fixes both. cef_host takes all its inputs by path,
	 so it needs nothing above stdio."
	cmd := '/usr/bin/perl -MPOSIX -e ''for (3..1023) { POSIX::close($_) }; exec @ARGV or die $!'' -- "',
		WebViewCefMorph binaryPath, '" "', url, '" ', w printString, ' ', h printString,
		' "', shmPath, '" "', inputPath, '" "', self cachePath, '" >/tmp/wv-cef-', id printString,
		'.log 2>&1 & echo $! > "', pidPath, '"'.
	LibC runCommand: cmd.
	WebViewProjectPlan log: 'launched cef_host #', id printString, ' at ', w printString, 'x', h printString
]

{ #category : 'scripting' }
WebViewCefMorph >> loadCount [
	^ self valueOfProperty: #wvLoadCount ifAbsent: [ 0 ]
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

{ #category : 'events' }
WebViewCefMorph >> mouseDown: anEvent [
	self withErrorLog: [
		| p |
		self comeToFront.
		self raiseStayOnTopSiblings.
		p := self toBrowserCoords: anEvent position.
		self writeCommand: { 'type' -> 'down'. 'x' -> p x. 'y' -> p y } asDictionary.
		self takeKeyboardFocus ]
		label: 'mouseDown'
]

{ #category : 'event handling' }
WebViewCefMorph >> mouseMove: anEvent [
	| p |
	anEvent anyButtonPressed ifFalse: [ ^ self ].
	p := self toBrowserCoords: anEvent position.
	self writeCommand: { 'type' -> 'move'. 'x' -> p x. 'y' -> p y. 'buttons' -> 1 } asDictionary
]

{ #category : 'event handling' }
WebViewCefMorph >> mouseUp: anEvent [
	self withErrorLog: [
		| p |
		p := self toBrowserCoords: anEvent position.
		self writeCommand: { 'type' -> 'up'. 'x' -> p x. 'y' -> p y } asDictionary ]
		label: 'mouseUp'
]

{ #category : 'event handling' }
WebViewCefMorph >> mouseWheel: anEvent [
	self withErrorLog: [
		| p dx dy step |
		p := self toBrowserCoords: anEvent position.
		step := 60. dx := 0. dy := 0.
		anEvent isUp ifTrue: [ dy := step ].
		anEvent isDown ifTrue: [ dy := step negated ].
		anEvent isLeft ifTrue: [ dx := step ].
		anEvent isRight ifTrue: [ dx := step negated ].
		(dx = 0 and: [ dy = 0 ]) ifFalse: [
			self writeCommand: { 'type' -> 'scroll'. 'x' -> p x. 'y' -> p y. 'dx' -> dx. 'dy' -> dy } asDictionary ] ]
		label: 'mouseWheel'
]

{ #category : 'scripting' }
WebViewCefMorph >> nextEvalId [
	| n |
	n := (self valueOfProperty: #wvEvalCounter ifAbsent: [ 0 ]) + 1.
	self setProperty: #wvEvalCounter toValue: n.
	^ n
]

{ #category : 'events' }
WebViewCefMorph >> onEvent: aSymbol do: aBlock [
	"Register aBlock (arg = the parsed event Dictionary) for a reverse event.
	Events: #loadStart #loadEnd #loadingState #loadError #title #js.
	Returns the block so it can be used to remove it later."
	| cbs |
	cbs := self valueOfProperty: #wvCallbacks ifAbsent: [ nil ].
	cbs ifNil: [ cbs := IdentityDictionary new. self setProperty: #wvCallbacks toValue: cbs ].
	(cbs at: aSymbol ifAbsentPut: [ OrderedCollection new ]) add: aBlock.
	^ aBlock
]

{ #category : 'events' }
WebViewCefMorph >> onJs: aBlock [
	"Any window.pharo.emit(name, data) call (arg has #name #data)."
	^ self onEvent: #js do: aBlock
]

{ #category : 'events' }
WebViewCefMorph >> onJs: aName do: aBlock [
	"window.pharo.emit(aName, data) with a specific name (arg has #name #data)."
	^ self onEvent: ('js:', aName) asSymbol do: aBlock
]

{ #category : 'events' }
WebViewCefMorph >> onLoadError: aBlock [
	"Arg has #errorCode #errorText #url."
	^ self onEvent: #loadError do: aBlock
]

{ #category : 'events' }
WebViewCefMorph >> onLoadStart: aBlock [
	^ self onEvent: #loadStart do: aBlock
]

{ #category : 'events' }
WebViewCefMorph >> onPageLoad: aBlock [
	"Fires when the main frame finishes loading (arg has #url, #httpStatus)."
	^ self onEvent: #loadEnd do: aBlock
]

{ #category : 'events' }
WebViewCefMorph >> onTitleChange: aBlock [
	"Arg has #title."
	^ self onEvent: #title do: aBlock
]

{ #category : 'events' }
WebViewCefMorph >> pumpEvents [
	"Tail the reverse event file and dispatch complete JSON lines to callbacks."
	| ref off size newBytes lastNl chunk |
	ref := self eventsPath asFileReference.
	ref exists ifFalse: [ ^ self ].
	off := self valueOfProperty: #wvEventsOffset ifAbsent: [ 0 ].
	size := ref size.
	size < off ifTrue: [ off := 0 ].
	size <= off ifTrue: [ self setProperty: #wvEventsOffset toValue: size. ^ self ].
	newBytes := ref binaryReadStreamDo: [ :s | s skip: off. s next: size - off ].
	lastNl := 0.
	1 to: newBytes size do: [ :i | (newBytes at: i) = 10 ifTrue: [ lastNl := i ] ].
	lastNl = 0 ifTrue: [ ^ self ].
	chunk := newBytes copyFrom: 1 to: lastNl.
	self setProperty: #wvEventsOffset toValue: off + lastNl.
	chunk utf8Decoded lines do: [ :ln |
		ln trimBoth ifNotEmpty: [ :s | self dispatchEventLine: s ] ]
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

{ #category : 'layering' }
WebViewCefMorph >> raiseStayOnTopSiblings [
	"Keep transient overlays (e.g. a search window) above this webview after it comes to
	 front. Any world-level morph flagged #wvStayOnTop is re-raised above us. Generic hook;
	 the client sets the flag."
	self world ifNotNil: [ :w |
		(w submorphs select: [ :m | (m ~~ self) and: [ m hasProperty: #wvStayOnTop ] ])
			do: [ :m | m comeToFront ] ]
]

{ #category : 'screenshot' }
WebViewCefMorph >> saveScreenshotTo: aPathStringOrRef [
	"Write a PNG of the current browser frame. Answers the FileReference, or nil."
	| form ref |
	form := self asForm.
	form ifNil: [ ^ nil ].
	ref := aPathStringOrRef asFileReference.
	ref parent ensureCreateDirectory.
	form writePNGFileNamed: ref fullName.
	^ ref
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
	self pumpEvents.
	self ensureShm ifFalse: [ ^ self ].
	shm alive ifFalse: [ ^ self ].
	self maybeResize.
	seq := shm seq.
	seq = lastSeq ifTrue: [ ^ self ].
	noSkip := seq = (lastSeq + 1).
	lastSeq := seq.
	self pushFrameDirty: noSkip.
	"Present the new browser frame directly instead of damaging our Morphic bounds.
	 self changed would re-render the world Form around us every frame, and at the
	 clip edge against opaque morphs in front (real z-order) that lost a 1px column,
	 leaving our white backing as a seam through their content. Presenting the overlay
	 (same world texture + fresh browser pixels) avoids re-rendering the Form at all."
	self formRendererOrNil
		ifNotNil: [ :r | r useDeferredUpdates ]
		ifNil: [ self changed ] ]
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

{ #category : 'private' }
WebViewCefMorph >> withErrorLog: aBlock label: aString [
	^ aBlock on: Error do: [ :e |
		WebViewProjectPlan log: aString, ' ERROR: ', e class name, ' - ', (e messageText ifNil: ['nil']).
		nil ]
]

{ #category : 'private' }
WebViewCefMorph >> writeCommand: aDictionary [
	"Append one JSON command line to the CEF host input channel (properly escaped)."
	[ | line stream |
	line := String streamContents: [ :s |
		s nextPut: ${.
		aDictionary keysAndValuesDo: [ :k :v |
			self jsonStringOn: s put: k asString.
			s nextPut: $:.
			v isNumber
				ifTrue: [ s nextPutAll: v printString ]
				ifFalse: [ (v isKindOf: Boolean)
					ifTrue: [ s nextPutAll: (v ifTrue: [ 'true' ] ifFalse: [ 'false' ]) ]
					ifFalse: [ self jsonStringOn: s put: v asString ] ].
			s nextPut: $, ].
		s nextPutAll: '"_":0}' ].
	stream := (File named: inputPath) openForAppend.
	[ stream nextPutAll: line utf8Encoded; nextPut: Character lf asInteger ] ensure: [ stream close ] ]
		on: Error do: [ :e | WebViewProjectPlan log: 'CefMorph writeCommand error: ', e messageText ]
]
