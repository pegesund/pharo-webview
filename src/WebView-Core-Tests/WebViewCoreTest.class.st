Class {
	#name : 'WebViewCoreTest',
	#superclass : 'TestCase',
	#category : 'WebView-Core-Tests',
	#package : 'WebView-Core-Tests'
}

{ #category : 'tests' }
WebViewCoreTest >> testFormRendererOverridesAllPresentSites [
	#(copyAndPresentTextureRectangle: updateAll useDeferredUpdates copyOverlay validateOverlay clearOverlay overlayForm:bounds: destroy)
		do: [ :sel | self assert: (WebViewFormRenderer includesSelector: sel) description: sel asString ]
]

{ #category : 'tests' }
WebViewCoreTest >> testPatternMorphRendersWithoutWorld [
	| m |
	m := WebViewTestPatternMorph new.
	m renderPattern.
	m step.
	self assert: m extent equals: 320 @ 240.
	m delete
]

{ #category : 'tests' }
WebViewCoreTest >> testPlanM0IsDone [
	self assert: (WebViewProjectPlan status at: #M0) equals: #done.
	self assert: (WebViewProjectPlan reportAt: #M0) isNotNil
]

{ #category : 'tests' }
WebViewCoreTest >> testWorldRendererRegistration [
	self assert: WebViewWorldRenderer priority equals: 3.
	self deny: (WebViewWorldRenderer isApplicableFor: nil).
	self assert: (AbstractWorldRenderer allSubclasses includes: WebViewWorldRenderer)
]
