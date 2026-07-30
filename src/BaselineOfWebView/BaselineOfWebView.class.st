Class {
	#name : 'BaselineOfWebView',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfWebView',
	#package : 'BaselineOfWebView'
}

{ #category : 'baselines' }
BaselineOfWebView >> baseline: spec [
	<baseline>
	spec for: #common do: [
		"Bloc is only needed for the optional WebView-Bloc host (BlElement-based).
		 Kept out of #default so Morphic-only users don't pull in Bloc."
		spec
			baseline: 'Bloc'
			with: [ spec repository: 'github://pharo-graphics/Bloc:master/src' ].
		spec
			package: 'WebView-FFI';
			package: 'WebView-Core' with: [ spec requires: #('WebView-FFI') ];
			package: 'WebView-Example' with: [ spec requires: #('WebView-Core') ];
			package: 'WebView-Bloc' with: [ spec requires: #('WebView-Core' 'Bloc') ];
			package: 'WebView-Planning';
			package: 'WebView-Core-Tests' with: [ spec requires: #('WebView-Core') ].
		spec
			group: 'default' with: #('WebView-Core' 'WebView-FFI' 'WebView-Example');
			group: 'core' with: #('WebView-Core' 'WebView-FFI');
			group: 'bloc' with: #('WebView-Core' 'WebView-FFI' 'WebView-Bloc');
			group: 'tests' with: #('WebView-Core-Tests') ]
]
