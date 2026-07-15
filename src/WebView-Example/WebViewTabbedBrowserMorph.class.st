Class {
	#name : 'WebViewTabbedBrowserMorph',
	#superclass : 'Morph',
	#instVars : [
		'tabs',
		'activeIndex',
		'tabBar',
		'backBtn',
		'fwdBtn',
		'reloadBtn',
		'goBtn',
		'addressField',
		'newTabBtn',
		'currentUrl',
		'tabBarHeight',
		'toolbarHeight'
	],
	#category : 'WebView-Example',
	#package : 'WebView-Example'
}

{ #category : 'tabs' }
WebViewTabbedBrowserMorph >> activateTab: index [
	(index between: 1 and: tabs size) ifFalse: [ ^ self ].
	activeIndex := index.
	tabs doWithIndex: [ :wv :i |
		i = index ifTrue: [ wv show ] ifFalse: [ wv hide ] ].
	self layoutWidgets.
	self rebuildTabBar.
	self changed
]

{ #category : 'tabs' }
WebViewTabbedBrowserMorph >> activeWebview [
	^ (activeIndex between: 1 and: tabs size) ifTrue: [ tabs at: activeIndex ] ifFalse: [ nil ]
]

{ #category : 'tabs' }
WebViewTabbedBrowserMorph >> addBlankTab [
	self addTab: 'https://example.com'
]

{ #category : 'tabs' }
WebViewTabbedBrowserMorph >> addTab: aUrl [
	| wv |
	wv := WebViewCefMorph new.
	wv url: aUrl.
	self addMorph: wv.
	tabs add: wv.
	self activateTab: tabs size.
	^ wv
]

{ #category : 'address model' }
WebViewTabbedBrowserMorph >> addressAccepted: aText [
	currentUrl := aText asString trimmed.
	self navigateToAddress.
	^ true
]

{ #category : 'address model' }
WebViewTabbedBrowserMorph >> addressText [ ^ currentUrl asText
]

{ #category : 'building' }
WebViewTabbedBrowserMorph >> buildToolbar [
	backBtn := self makeButton: '<' action: #goBack.
	fwdBtn := self makeButton: '>' action: #goForward.
	reloadBtn := self makeButton: 'Reload' action: #reload.
	goBtn := self makeButton: 'Go' action: #navigateToAddress.
	newTabBtn := self makeButton: '+ Tab' action: #addBlankTab.
	addressField := RubTextFieldMorph new on: self text: #addressText accept: #addressAccepted: readSelection: nil menu: nil; yourself.
	addressField acceptOnCR: true.
	self addMorph: backBtn; addMorph: fwdBtn; addMorph: reloadBtn; addMorph: addressField; addMorph: goBtn; addMorph: newTabBtn
]

{ #category : 'tabs' }
WebViewTabbedBrowserMorph >> closeTab: index [
	| wv |
	(index between: 1 and: tabs size) ifFalse: [ ^ self ].
	wv := tabs at: index.
	tabs removeIndex: index.
	wv delete.
	tabs isEmpty
		ifTrue: [ self addTab: 'https://example.com' ]
		ifFalse: [ self activateTab: (activeIndex min: tabs size) max: 1 ]
]

{ #category : 'submorphs-add/remove' }
WebViewTabbedBrowserMorph >> delete [
	tabs do: [ :wv | [ wv delete ] on: Error do: [:e|] ].
	super delete
]

{ #category : 'layout' }
WebViewTabbedBrowserMorph >> extent: aPoint [
	super extent: aPoint.
	(tabBar notNil and: [ backBtn notNil ]) ifTrue: [ self layoutWidgets ]
]

{ #category : 'actions' }
WebViewTabbedBrowserMorph >> goBack [ self activeWebview ifNotNil: [:wv | wv writeCommand: { 'type'->'back' } asDictionary ]
]

{ #category : 'actions' }
WebViewTabbedBrowserMorph >> goForward [ self activeWebview ifNotNil: [:wv | wv writeCommand: { 'type'->'forward' } asDictionary ]
]

{ #category : 'initialization' }
WebViewTabbedBrowserMorph >> initialize [
	super initialize.
	tabs := OrderedCollection new.
	activeIndex := 0.
	currentUrl := ''.
	tabBarHeight := 28.
	toolbarHeight := 34.
	self extent: 900 @ 620.
	self color: (Color gray: 0.85).
	self buildToolbar.
	tabBar := Morph new color: (Color gray: 0.75); yourself.
	self addMorph: tabBar.
	self addTab: 'https://example.com'
]

{ #category : 'stepping' }
WebViewTabbedBrowserMorph >> intoWorld: aWorld [
	super intoWorld: aWorld.
	self comeToFront.
	self layoutWidgets.
	self startStepping
]

{ #category : 'layout' }
WebViewTabbedBrowserMorph >> layoutWidgets [
	| x y fh bw wv |
	tabBar position: self topLeft; extent: self width @ tabBarHeight.
	self rebuildTabBar.
	y := self top + tabBarHeight + 4.
	fh := toolbarHeight - 8.
	x := self left + 4.
	{ backBtn. fwdBtn. reloadBtn } do: [ :btn | btn position: x @ y; extent: 40 @ fh. x := x + 44 ].
	goBtn extent: 40 @ fh.
	newTabBtn extent: 60 @ fh.
	bw := self right - 4 - 60 - 4 - 40 - 4 - x.
	addressField position: x @ y; extent: bw @ fh.
	x := x + bw + 4.
	goBtn position: x @ y. x := x + 44.
	newTabBtn position: x @ y.
	wv := self activeWebview.
	wv ifNotNil: [
		wv position: self left @ (self top + tabBarHeight + toolbarHeight).
		wv extent: self width @ (self height - tabBarHeight - toolbarHeight) ]
]

{ #category : 'building' }
WebViewTabbedBrowserMorph >> makeButton: aLabel action: aSelector [
	| btn |
	btn := SimpleButtonMorph new.
	btn target: self; actionSelector: aSelector; label: aLabel.
	btn color: (Color gray: 0.82); borderWidth: 1; borderColor: (Color gray: 0.6).
	^ btn
]

{ #category : 'actions' }
WebViewTabbedBrowserMorph >> navigateToAddress [
	self activeWebview ifNotNil: [:wv |
		currentUrl notEmpty ifTrue: [ wv writeCommand: { 'type'->'navigate'. 'url'->currentUrl } asDictionary ] ]
]

{ #category : 'tabs' }
WebViewTabbedBrowserMorph >> rebuildTabBar [
	| x th |
	tabBar removeAllMorphs.
	th := tabBarHeight - 4.
	x := 2.
	tabs doWithIndex: [ :wv :i |
		| tabBtn closeBtn |
		tabBtn := SimpleButtonMorph new.
		tabBtn target: self; actionSelector: #activateTab:; arguments: { i }; label: 'Tab ', i printString.
		tabBtn color: (i = activeIndex ifTrue: [ Color r: 0.75 g: 0.88 b: 1.0 ] ifFalse: [ Color gray: 0.7 ]).
		tabBtn borderWidth: 1; borderColor: (Color gray: 0.5).
		tabBtn position: (tabBar left + x) @ (tabBar top + 2); extent: 70 @ th.
		tabBar addMorph: tabBtn.
		x := x + 72.
		closeBtn := SimpleButtonMorph new.
		closeBtn target: self; actionSelector: #closeTab:; arguments: { i }; label: 'x'.
		closeBtn color: (Color gray: 0.6); borderWidth: 1; borderColor: (Color gray: 0.5).
		closeBtn position: (tabBar left + x) @ (tabBar top + 2); extent: 20 @ th.
		tabBar addMorph: closeBtn.
		x := x + 26 ]
]

{ #category : 'actions' }
WebViewTabbedBrowserMorph >> reload [ self activeWebview ifNotNil: [:wv | wv writeCommand: { 'type'->'reload' } asDictionary ]
]

{ #category : 'stepping' }
WebViewTabbedBrowserMorph >> step [
	"Reflect the active tab current URL in the address bar."

	[
		| wv sp newUrl |
		wv := self activeWebview ifNil: [ ^ self ].
		sp := wv statusPath.
		sp asFileReference exists ifFalse: [ ^ self ].
		newUrl := sp asFileReference contents trimBoth.
		newUrl = currentUrl ifTrue: [ ^ self ].
		(addressField notNil and: [ addressField hasKeyboardFocus ]) ifTrue: [ ^ self ].
		currentUrl := newUrl.
		addressField setText: currentUrl asText ]
		on: Error
		do: [ :e |  ]
]

{ #category : 'stepping' }
WebViewTabbedBrowserMorph >> stepTime [ ^ 200
]

{ #category : 'stepping' }
WebViewTabbedBrowserMorph >> wantsSteps [ ^ true
]
