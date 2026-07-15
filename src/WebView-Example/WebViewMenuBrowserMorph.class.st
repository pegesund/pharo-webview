"
A small example that demonstrates Morphs drawing OVER the live CEF browser
(z-order compositing, see WebViewFormRenderer occlusion clipping).

It embeds a WebViewCefMorph and shows a ""Steder"" button in a top bar. Clicking
the button pops up a dropdown menu (plain Morphs) that overlays the browser page;
picking an entry navigates the webview and closes the menu.

	WebViewMenuBrowserMorph open.

The menu panel is added as a front submorph of the widget, so it occludes the
browser texture — exactly the capability that alpha-hole/occlusion compositing
unlocked. Places live in the `places` ivar (label -> url associations).
"
Class {
	#name : 'WebViewMenuBrowserMorph',
	#superclass : 'Morph',
	#instVars : [
		'webview',
		'menuButton',
		'menuPanel',
		'barHeight',
		'places'
	],
	#category : 'WebView-Example',
	#package : 'WebView-Example'
}

{ #category : 'instance creation' }
WebViewMenuBrowserMorph class >> open [
	^ self new openInWorld
]

{ #category : 'building' }
WebViewMenuBrowserMorph >> buildBar [
	menuButton := SimpleButtonMorph new.
	menuButton target: self; actionSelector: #toggleMenu; label: 'Steder  ▾'.
	menuButton color: (Color r: 0.2 g: 0.45 b: 0.85); borderWidth: 0.
	menuButton label: 'Steder  ▾'.
	self addMorph: menuButton
]

{ #category : 'menu' }
WebViewMenuBrowserMorph >> buildMenuPanel [
	| panel rowH w y |
	rowH := 36. w := 220.
	panel := Morph new.
	panel color: (Color gray: 0.16); borderWidth: 1; borderColor: (Color gray: 0.45).
	panel extent: w @ (places size * rowH).
	y := 0.
	places do: [ :assoc | | row label |
		row := Morph new.
		row color: (Color gray: 0.16); borderWidth: 0.
		row extent: w @ rowH.
		row setProperty: #placeUrl toValue: assoc value.
		row setProperty: #menuRow toValue: true.
		row on: #mouseUp send: #chosePlace:from: to: self.
		row on: #mouseEnter send: #hiliteRow:from: to: self.
		row on: #mouseLeave send: #unhiliteRow:from: to: self.
		panel addMorph: row.
		row position: panel position + (0 @ y).
		label := StringMorph contents: assoc key.
		label color: Color white.
		row addMorph: label.
		label position: row position + (16 @ ((rowH - label height) // 2)).
		label lock.
		y := y + rowH ].
	^ panel
]

{ #category : 'building' }
WebViewMenuBrowserMorph >> buildWebview [
	webview := WebViewCefMorph new.
	webview url: (places first value).
	self addMorph: webview
]

{ #category : 'menu' }
WebViewMenuBrowserMorph >> chosePlace: anEvent from: aMorph [
	| url |
	url := aMorph valueOfProperty: #placeUrl.
	self closeMenu.
	url ifNotNil: [ self navigateTo: url ]
]

{ #category : 'menu' }
WebViewMenuBrowserMorph >> closeMenu [
	menuPanel ifNotNil: [ menuPanel delete. menuPanel := nil ]
]

{ #category : 'submorphs-add/remove' }
WebViewMenuBrowserMorph >> delete [
	webview ifNotNil: [ webview delete ].
	super delete
]

{ #category : 'layout' }
WebViewMenuBrowserMorph >> extent: aPoint [
	super extent: aPoint.
	(menuButton notNil and: [ webview notNil ]) ifTrue: [ self layoutWidgets ]
]

{ #category : 'menu' }
WebViewMenuBrowserMorph >> hiliteRow: anEvent from: aMorph [
	aMorph color: (Color r: 0.2 g: 0.45 b: 0.85)
]

{ #category : 'initialization' }
WebViewMenuBrowserMorph >> initialize [
	super initialize.
	barHeight := 38.
	places := {
		'BBC' -> 'https://www.bbc.com'.
		'Wikipedia' -> 'https://www.wikipedia.org'.
		'NRK' -> 'https://www.nrk.no'.
		'Hacker News' -> 'https://news.ycombinator.com' }.
	self extent: 960 @ 640.
	self color: (Color gray: 0.92).
	self buildBar.
	self buildWebview.
	self layoutWidgets
]

{ #category : 'layout' }
WebViewMenuBrowserMorph >> layoutWidgets [
	menuButton position: (self left + 8) @ (self top + 6); extent: 130 @ (barHeight - 12).
	webview position: self left @ (self top + barHeight).
	webview extent: self width @ (self height - barHeight)
]

{ #category : 'actions' }
WebViewMenuBrowserMorph >> navigateTo: aUrl [
	webview ifNotNil: [
		webview writeCommand: { 'type' -> 'navigate'. 'url' -> aUrl } asDictionary ]
]

{ #category : 'menu' }
WebViewMenuBrowserMorph >> openMenu [
	menuPanel := self buildMenuPanel.
	self addMorphFront: menuPanel.
	menuPanel position: menuButton bottomLeft + (0 @ 3).
	menuPanel comeToFront
]

{ #category : 'menu' }
WebViewMenuBrowserMorph >> toggleMenu [
	menuPanel ifNotNil: [ ^ self closeMenu ].
	self openMenu
]

{ #category : 'menu' }
WebViewMenuBrowserMorph >> unhiliteRow: anEvent from: aMorph [
	aMorph color: (Color gray: 0.16)
]

{ #category : 'accessing' }
WebViewMenuBrowserMorph >> webview [
	^ webview
]
