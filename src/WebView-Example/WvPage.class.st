"
A tiny Smalltalk browser-automation DSL over a WebViewCefMorph.

Because reads travel through the async JS bridge (delivered on the UI process),
an automation script must run OFF the UI process. Use `on:script:`, which forks
the script into a background process; then reads like `textOf:` block and return
their value synchronously — without freezing the UI.

	| m |
	m := WvPage openBrowserOn: 'https://en.wikipedia.org'.
	WvPage on: m script: [ :page |
		page fill: 'input[name=search]' with: 'Smalltalk-80'.
		page submit: 'input[name=search]'.        ""waits for the result page""
		Transcript showln: (page textOf: '#firstHeading').
		Transcript showln: (page count: 'a[href^=""/wiki/""]') printString ].

Actions: goto: waitForLoad waitFor: click: clickAndWait: fill:with: submit:
pressEnterIn: js: (fire-and-forget). Queries (block until the value returns):
textOf: textsOf: valueOf: attr:of: exists: count: title url eval:. Ready-made
demos: `WvPage hackerNewsDemoOn:` and `wikipediaSearchDemoOn:for:`.
"
Class {
	#name : 'WvPage',
	#superclass : 'Object',
	#instVars : [
		'morph',
		'loadMark',
		'stepMs'
	],
	#category : 'WebView-Example',
	#package : 'WebView-Example'
}

{ #category : 'demos' }
WvPage class >> hackerNewsDemoOn: aMorph [
	"Forked demo: drive Hacker News and log the top story titles + points."
	^ self on: aMorph script: [ :page | | titles n |
		page goto: 'https://news.ycombinator.com'.
		page waitForLoad.
		titles := page textsOf: '.titleline > a'.
		n := 6 min: titles size.
		WebViewProjectPlan log: 'Hacker News — top ', n printString, ' stories:'.
		1 to: n do: [ :i |
			WebViewProjectPlan log: '  ', i printString, '. ', (titles at: i) ] ]
]

{ #category : 'instance creation' }
WvPage class >> on: aWebViewCefMorph [
	^ self new setMorph: aWebViewCefMorph
]

{ #category : 'instance creation' }
WvPage class >> on: aWebViewCefMorph script: aBlock [
	"Run aBlock (which takes the page) in a BACKGROUND process so synchronous
	reads (textOf:, waitForLoad, …) work without freezing the UI. Returns the
	Process. Errors are logged, not silently swallowed."
	| page |
	page := self on: aWebViewCefMorph.
	^ [ [ aBlock value: page ]
		on: Error
		do: [ :e | WebViewProjectPlan log: 'WvPage script ERROR: ', e printString ] ] fork
]

{ #category : 'demos' }
WvPage class >> openBrowserOn: aUrl [
	"Open a fresh WebViewCefMorph on aUrl and answer it (call from UI process)."
	| m |
	m := WebViewCefMorph new.
	m url: aUrl; position: 300 @ 160; extent: 860 @ 580.
	m openInWorld; comeToFront.
	^ m
]

{ #category : 'demos' }
WvPage class >> wikipediaSearchDemoOn: aMorph for: aTerm [
	"Forked demo: search Wikipedia for aTerm and log the article heading + intro."
	^ self on: aMorph script: [ :page |
		page goto: 'https://en.wikipedia.org'.
		page waitForLoad.
		page fill: 'input[name=search]' with: aTerm.
		page submit: 'input[name=search]'.
		WebViewProjectPlan log: 'Wikipedia[', aTerm, '] -> ', (page textOf: '#firstHeading') printString.
		WebViewProjectPlan log: '  ', (((page textOf: '.mw-parser-output p') ifNil: [ '' ]) truncateTo: 160) ]
]

{ #category : 'querying' }
WvPage >> attr: attrName of: cssSelector [
	^ self eval: '(function(){var e=', (self q: cssSelector), '; return e?e.getAttribute(', (self jsStr: attrName), '):null})()'
]

{ #category : 'actions' }
WvPage >> click: cssSelector [
	"Click the first matching element (if any)."
	self js: 'var e=', (self q: cssSelector), '; if(e){e.scrollIntoView({block:"center"});e.click();}'.
	^ self
]

{ #category : 'actions' }
WvPage >> clickAndWait: cssSelector [
	"Click, then wait for the resulting navigation to finish."
	self mark; click: cssSelector; waitForLoad. ^ self
]

{ #category : 'querying' }
WvPage >> count: cssSelector [
	^ self eval: 'document.querySelectorAll(', (self jsStr: cssSelector), ').length'
]

{ #category : 'querying' }
WvPage >> eval: jsExpression [
	"Evaluate a JS expression and return its value (blocks this process)."
	^ morph evalJsSync: jsExpression
]

{ #category : 'querying' }
WvPage >> exists: cssSelector [
	^ (self eval: '!!', (self q: cssSelector)) = true
]

{ #category : 'actions' }
WvPage >> fill: cssSelector with: aString [
	"Set an input/textarea value and fire input+change events."
	self js: 'var e=', (self q: cssSelector), '; if(e){e.focus();e.value=', (self jsStr: aString),
		'; e.dispatchEvent(new Event("input",{bubbles:true}));e.dispatchEvent(new Event("change",{bubbles:true}));}'.
	^ self
]

{ #category : 'actions' }
WvPage >> goto: aUrl [
	"Navigate and remember the load mark so #waitForLoad can await completion."
	loadMark := morph loadCount.
	morph writeCommand: { 'type' -> 'navigate'. 'url' -> aUrl } asDictionary.
	^ self
]

{ #category : 'actions' }
WvPage >> js: jsSource [
	"Fire-and-forget JS (no return)."
	morph evalJs: jsSource. ^ self
]

{ #category : 'private' }
WvPage >> jsStr: aString [
	"aString as a JSON/JS double-quoted string literal (reuses the morph escaper)."
	^ String streamContents: [ :s | morph jsonStringOn: s put: aString asString ]
]

{ #category : 'actions' }
WvPage >> mark [
	"Snapshot the current load count before a navigating action."
	loadMark := morph loadCount. ^ self
]

{ #category : 'accessing' }
WvPage >> morph [ ^ morph
]

{ #category : 'actions' }
WvPage >> pressEnterIn: cssSelector [
	"Dispatch an Enter keydown on an element (triggers most search boxes)."
	self js: 'var e=', (self q: cssSelector), '; if(e){e.dispatchEvent(new KeyboardEvent("keydown",{key:"Enter",code:"Enter",keyCode:13,which:13,bubbles:true}));}'.
	^ self
]

{ #category : 'private' }
WvPage >> q: cssSelector [
	"JS source for document.querySelector(selector)."
	^ 'document.querySelector(', (self jsStr: cssSelector), ')'
]

{ #category : 'private' }
WvPage >> setMorph: aMorph [
	morph := aMorph.
	stepMs := 100.
	loadMark := 0.
	morph ensureLoadCounter.
	^ self
]

{ #category : 'actions' }
WvPage >> submit: cssSelector [
	"Submit the form containing (or matching) the selector."
	self mark.
	self js: 'var e=', (self q: cssSelector), '; if(e){(e.form||e).submit();}'.
	self waitForLoad. ^ self
]

{ #category : 'querying' }
WvPage >> textOf: cssSelector [
	^ self eval: '(('  , (self q: cssSelector), '||{}).textContent||"").trim()'
]

{ #category : 'querying' }
WvPage >> textsOf: cssSelector [
	^ (self eval: 'Array.from(document.querySelectorAll(', (self jsStr: cssSelector), ')).map(function(e){return (e.textContent||"").trim()})') ifNil: [ #() ]
]

{ #category : 'querying' }
WvPage >> title [
	^ self eval: 'document.title'
]

{ #category : 'querying' }
WvPage >> url [
	^ self eval: 'location.href'
]

{ #category : 'querying' }
WvPage >> valueOf: cssSelector [
	^ self eval: '(', (self q: cssSelector), '||{}).value'
]

{ #category : 'waiting' }
WvPage >> waitFor: cssSelector [
	"Poll until an element matching the selector exists (or ~10s)."
	| ticks |
	ticks := 100.
	[ self exists: cssSelector ] whileFalse: [
		(ticks := ticks - 1) <= 0 ifTrue: [ WebViewProjectPlan log: 'waitFor timeout: ', cssSelector. ^ false ].
		(Delay forMilliseconds: stepMs) wait ].
	^ true
]

{ #category : 'waiting' }
WvPage >> waitForLoad [
	"Block until a page load completes after the last navigating action."
	^ self waitForLoadTimeout: 20
]

{ #category : 'waiting' }
WvPage >> waitForLoadTimeout: seconds [
	| ticks |
	ticks := (seconds * 1000 / stepMs) rounded max: 1.
	[ morph loadCount > loadMark ] whileFalse: [
		(ticks := ticks - 1) <= 0 ifTrue: [ WebViewProjectPlan log: 'waitForLoad timeout'. ^ self ].
		(Delay forMilliseconds: stepMs) wait ].
	"give scripts a beat to run after DOMContentLoaded"
	(Delay forMilliseconds: 250) wait.
	^ self
]
