Class {
	#name : 'WebViewBrowserMorph',
	#superclass : 'Morph',
	#instVars : [
		'webview',
		'addressField',
		'backBtn',
		'fwdBtn',
		'reloadBtn',
		'goBtn',
		'toolbarHeight',
		'currentUrl',
		'statusPath',
		'lastStatusRead'
	],
	#category : 'WebView-Example',
	#package : 'WebView-Example'
}

{ #category : 'address model' }
WebViewBrowserMorph >> addressAccepted: aText [

	currentUrl := aText asString trimBoth.
	self navigateToAddress.
	^ true
]

{ #category : 'address model' }
WebViewBrowserMorph >> addressText [
	"Model getter for the address field."
	^ currentUrl asText
]

{ #category : 'building' }
WebViewBrowserMorph >> buildToolbar [
	backBtn := self makeButton: '<' action: #goBack.
	fwdBtn := self makeButton: '>' action: #goForward.
	reloadBtn := self makeButton: 'Reload' action: #reload.
	goBtn := self makeButton: 'Go' action: #navigateToAddress.
	addressField := RubTextFieldMorph new
		on: self text: #addressText accept: #addressAccepted: readSelection: nil menu: nil;
		yourself.
	addressField acceptOnCR: true.
	self addMorph: backBtn; addMorph: fwdBtn; addMorph: reloadBtn; addMorph: addressField; addMorph: goBtn
]

{ #category : 'building' }
WebViewBrowserMorph >> buildWebview [
	webview := WebViewCefMorph new.
	self addMorph: webview
]

{ #category : 'submorphs-add/remove' }
WebViewBrowserMorph >> delete [
	webview ifNotNil: [ webview delete ].
	super delete
]

{ #category : 'layout' }
WebViewBrowserMorph >> extent: aPoint [
	super extent: aPoint.
	(backBtn notNil and: [ webview notNil ]) ifTrue: [ self layoutWidgets ]
]

{ #category : 'actions' }
WebViewBrowserMorph >> goBack [ self sendNav: 'back'
]

{ #category : 'actions' }
WebViewBrowserMorph >> goForward [ self sendNav: 'forward'
]

{ #category : 'initialization' }
WebViewBrowserMorph >> initialize [
	super initialize.
	toolbarHeight := 34.
	currentUrl := ''.
	statusPath := '/tmp/wv-cef.input.status'.
	lastStatusRead := 0.
	self extent: 800 @ (600 + toolbarHeight).
	self color: (Color gray: 0.9).
	self buildToolbar.
	self buildWebview.
	self layoutWidgets
]

{ #category : 'stepping' }
WebViewBrowserMorph >> intoWorld: aWorld [
	super intoWorld: aWorld.
	self startStepping
]

{ #category : 'layout' }
WebViewBrowserMorph >> layoutWidgets [
	| x y bw fh |
	y := self top + 4.
	fh := toolbarHeight - 8.
	x := self left + 4.
	{ backBtn. fwdBtn. reloadBtn } do: [ :btn |
		btn position: x @ y; extent: 40 @ fh.
		x := x + 44 ].
	goBtn extent: 40 @ fh.
	bw := self right - 4 - 40 - 4 - x.
	addressField position: x @ y; extent: bw @ fh.
	x := x + bw + 4.
	goBtn position: x @ y.
	webview position: self left @ (self top + toolbarHeight).
	webview extent: self width @ (self height - toolbarHeight)
]

{ #category : 'building' }
WebViewBrowserMorph >> makeButton: aLabel action: aSelector [
	| btn |
	btn := SimpleButtonMorph new.
	btn target: self; actionSelector: aSelector; label: aLabel.
	btn color: (Color gray: 0.8); borderWidth: 1; borderColor: (Color gray: 0.6).
	^ btn
]

{ #category : 'actions' }
WebViewBrowserMorph >> navigateToAddress [
	| u |
	u := currentUrl.
	(u notEmpty) ifTrue: [
		webview writeCommand: { 'type' -> 'navigate'. 'url' -> u } asDictionary ]
]

{ #category : 'actions' }
WebViewBrowserMorph >> reload [ self sendNav: 'reload'
]

{ #category : 'actions' }
WebViewBrowserMorph >> sendNav: aType [
	webview writeCommand: { 'type' -> aType } asDictionary
]

{ #category : 'stepping' }
WebViewBrowserMorph >> step [
	"Poll the webview status file for the current URL; reflect it in the address bar
	unless the user is editing it."

	[
		| ref newUrl sp |
		webview ifNil: [ ^ self ].
		sp := webview statusPath.
		ref := sp asFileReference.
		ref exists ifFalse: [ ^ self ].
		newUrl := ref contents trimBoth.
		newUrl = currentUrl ifTrue: [ ^ self ].
		(addressField notNil and: [ addressField hasKeyboardFocus ]) ifTrue: [ ^ self ].
		currentUrl := newUrl.
		addressField ifNotNil: [ addressField setText: currentUrl asText ] ]
		on: Error
		do: [ :e |  ]
]

{ #category : 'stepping' }
WebViewBrowserMorph >> stepTime [ ^ 200
]

{ #category : 'accessing' }
WebViewBrowserMorph >> url: aString [
	currentUrl := aString.
	webview ifNotNil: [ webview url: aString ].
	addressField ifNotNil: [ addressField setText: aString asText ]
]

{ #category : 'stepping' }
WebViewBrowserMorph >> wantsSteps [ ^ true
]

{ #category : 'accessing' }
WebViewBrowserMorph >> webview [ ^ webview
]

{ #category : 'private' }
WebViewBrowserMorph >> webviewInputPath [
	^ webview instVarNamed: 'inputPath'
]
