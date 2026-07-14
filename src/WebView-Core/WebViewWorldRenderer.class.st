Class {
	#name : 'WebViewWorldRenderer',
	#superclass : 'OSWorldRenderer',
	#classVars : [
		'Enabled'
	],
	#category : 'WebView-Core',
	#package : 'WebView-Core'
}

{ #category : 'accessing' }
WebViewWorldRenderer class >> disable [
	Enabled := false
]

{ #category : 'accessing' }
WebViewWorldRenderer class >> enable [
	Enabled := true
]

{ #category : 'accessing' }
WebViewWorldRenderer class >> enabled [
	^ Enabled == true
]

{ #category : 'accessing' }
WebViewWorldRenderer class >> isApplicableFor: aWorld [
	"Guarded by an explicit enable flag so an image restart never picks this renderer
	while it is experimental. Enable with: WebViewWorldRenderer enable"
	^ self enabled and: [ super isApplicableFor: aWorld ]
]

{ #category : 'accessing' }
WebViewWorldRenderer class >> priority [
	^ 3
]

{ #category : 'accessing' }
WebViewWorldRenderer >> osWindowRenderer [
	"Same lazy creation as super, but installs a WebViewFormRenderer."
	osWindow ifNil: [ ^ nil ].
	^ osWindow renderer ifNil: [
		osWindow backendWindow renderer: (WebViewFormRenderer new
			form: display;
			backendWindow: osWindow backendWindow;
			yourself).
		osWindow renderer ]
]
