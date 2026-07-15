"
A tiny Smalltalk browser-automation + assertion DSL over a WebViewCefMorph.

Because reads travel through the async JS bridge (delivered on the UI process),
an automation script must run OFF the UI process. Use `on:script:` (or the test
runner `test:on:do:`), which forks the script into a background process; then
reads like `textOf:` block and return their value synchronously.

	| m |
	m := WvPage openBrowserOn: 'https://en.wikipedia.org'.
	WvPage test: 'Wikipedia search' on: m do: [ :page |
		page assertExists: 'input[name=search]'.
		page fill: 'input[name=search]' with: 'Smalltalk-80'.
		page submit: 'input[name=search]'.               ""waits for the result page""
		page assertTitleIncludes: 'Smalltalk'.
		page assertText: '#firstHeading' equals: 'Smalltalk'.
		page assertCount: 'a[href^=""/wiki/""]' atLeast: 10 ].

Actions: goto: waitForLoad waitFor: click: clickAndWait: fill:with: submit:
pressEnterIn: js:. Queries (block until the value returns): textOf: textsOf:
valueOf: attr:of: exists: count: title url eval:.

Assertions log each passing check and signal WvAssertionFailed on the first
failure: assert: assert:describe: assertExists: assertAbsent: assertText:equals:
assertText:includes: assertCount:is: assertCount:atLeast: assertTitleIncludes:
assertUrlIncludes:. `test:on:do:` wraps a named test and logs a PASS/FAIL/ERROR
summary with the passing-check count.

Demos: `WvPage hackerNewsDemoOn:`, `wikipediaSearchDemoOn:for:`.
"
Class {
	#name : 'WvPage',
	#superclass : 'Object',
	#instVars : [
		'morph',
		'loadMark',
		'stepMs',
		'passCount'
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

{ #category : 'testing' }
WvPage class >> test: aName on: aMorph do: aBlock [
	"Run aBlock (which takes a WvPage) as a named test in a background process.
	Logs each passing assert, then a PASS/FAIL/ERROR summary. Returns the Process."
	| page |
	page := self on: aMorph.
	WebViewProjectPlan log: '── test: ', aName.
	^ [
		[ [ aBlock value: page.
		    WebViewProjectPlan log: '✓ PASS: ', aName, ' (', page assertPassCount printString, ' checks)' ]
			on: WvAssertionFailed
			do: [ :e | WebViewProjectPlan log: '✗ FAIL: ', aName, ' — ', e messageText,
				' (after ', page assertPassCount printString, ' passing checks)' ] ]
		on: Error
		do: [ :e | WebViewProjectPlan log: '✗ ERROR: ', aName, ' — ', e printString ] ] fork
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

{ #category : 'asserting' }
WvPage >> assert: aBoolean [
	^ self assert: aBoolean describe: 'assertion'
]

{ #category : 'asserting' }
WvPage >> assert: aBoolean describe: aDescription [
	"Log a passing check; signal WvAssertionFailed on a failing one."
	aBoolean == true
		ifTrue: [ passCount := self assertPassCount + 1.
			WebViewProjectPlan log: '  ✓ ', aDescription ]
		ifFalse: [ WvAssertionFailed signal: aDescription ].
	^ self
]

{ #category : 'asserting' }
WvPage >> assertAbsent: cssSelector [
	^ self assert: (self exists: cssSelector) not describe: 'absent: ', cssSelector
]

{ #category : 'asserting' }
WvPage >> assertCount: cssSelector atLeast: minimum [
	| n ok |
	n := self count: cssSelector.
	ok := (n isNil not) and: [ n >= minimum ].
	^ self assert: ok describe: ('count ', cssSelector printString, ' >= ', minimum printString),
		(ok ifTrue: [ '' ] ifFalse: [ ' — got ', n printString ])
]

{ #category : 'asserting' }
WvPage >> assertCount: cssSelector is: expected [
	| n ok |
	n := self count: cssSelector.
	ok := n = expected.
	^ self assert: ok describe: ('count ', cssSelector printString, ' = ', expected printString),
		(ok ifTrue: [ '' ] ifFalse: [ ' — got ', n printString ])
]

{ #category : 'asserting' }
WvPage >> assertExists: cssSelector [
	^ self assert: (self exists: cssSelector) describe: 'exists: ', cssSelector
]

{ #category : 'asserting' }
WvPage >> assertPassCount [
	^ passCount ifNil: [ 0 ]
]

{ #category : 'asserting' }
WvPage >> assertText: cssSelector equals: expected [
	| actual ok |
	actual := self textOf: cssSelector.
	ok := actual = expected.
	^ self assert: ok describe: ('text of ', cssSelector printString, ' = ', expected printString),
		(ok ifTrue: [ '' ] ifFalse: [ ' — got ', actual printString ])
]

{ #category : 'asserting' }
WvPage >> assertText: cssSelector includes: substring [
	| actual ok |
	actual := self textOf: cssSelector.
	ok := actual notNil and: [ actual includesSubstring: substring ].
	^ self assert: ok describe: ('text of ', cssSelector printString, ' includes ', substring printString),
		(ok ifTrue: [ '' ] ifFalse: [ ' — got ', actual printString ])
]

{ #category : 'asserting' }
WvPage >> assertTitleIncludes: substring [
	| t ok |
	t := self title.
	ok := t notNil and: [ t includesSubstring: substring ].
	^ self assert: ok describe: ('title includes ', substring printString),
		(ok ifTrue: [ '' ] ifFalse: [ ' — got ', t printString ])
]

{ #category : 'asserting' }
WvPage >> assertUrlIncludes: substring [
	| u ok |
	u := self url.
	ok := u notNil and: [ u includesSubstring: substring ].
	^ self assert: ok describe: ('url includes ', substring printString),
		(ok ifTrue: [ '' ] ifFalse: [ ' — got ', u printString ])
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
