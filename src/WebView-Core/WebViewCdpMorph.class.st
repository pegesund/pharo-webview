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

{ #category : 'stepping' }
WebViewCdpMorph >> intoWorld: aWorld [
	super intoWorld: aWorld.
	self startStepping
]

{ #category : 'frames' }
WebViewCdpMorph >> loadCurrentFrame [
	"Decode frame.png into a 32-bit Form. Returns the Form or nil on any error."
	^ [ ImageReadWriter formFromFileNamed: self framePath ]
		on: Error
		do: [ :e | WebViewProjectPlan log: 'CDP decode error: ', e messageText. nil ]
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

{ #category : 'accessing' }
WebViewCdpMorph >> url: aString [
	url := aString
]

{ #category : 'stepping' }
WebViewCdpMorph >> wantsSteps [
	^ true
]
