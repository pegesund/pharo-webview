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
		spec
			package: 'WebView-FFI';
			package: 'WebView-Core' with: [ spec requires: #('WebView-FFI') ];
			package: 'WebView-Example' with: [ spec requires: #('WebView-Core') ];
			package: 'WebView-Planning';
			package: 'WebView-Core-Tests' with: [ spec requires: #('WebView-Core') ].
		spec
			group: 'default' with: #('WebView-Core' 'WebView-FFI' 'WebView-Example');
			group: 'core' with: #('WebView-Core' 'WebView-FFI');
			group: 'tests' with: #('WebView-Core-Tests') ]
]
