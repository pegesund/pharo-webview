Class {
	#name : 'WvShim',
	#superclass : 'Object',
	#instVars : [
		'handle'
	],
	#category : 'WebView-FFI',
	#package : 'WebView-FFI'
}

{ #category : 'library' }
WvShim class >> libraryPath [
	^ '/Users/pegesund/dev/pharo-webview/shim/target/release/libwvshim.dylib'
]

{ #category : 'ffi' }
WvShim class >> version [
	^ self ffiCall: #(uint32 wv_version()) library: WvShim libraryPath
]

{ #category : 'lifecycle' }
WvShim >> destroy [
	self isOpen ifFalse: [ ^ self ].
	self primDestroy.
	handle := nil
]

{ #category : 'frames' }
WvShim >> dirtyRects [
	"Answer the current frame dirty rects as Rectangles (max 64)."
	| mem n rects |
	self isOpen ifFalse: [ ^ #() ].
	mem := ExternalAddress allocate: 64 * 4 * 4.
	[ n := self primDirtyRects: mem max: 64.
	rects := (1 to: n) collect: [ :i |
		| base |
		base := (i - 1) * 16.
		((mem signedLongAt: base + 1) @ (mem signedLongAt: base + 5))
			extent: ((mem signedLongAt: base + 9) @ (mem signedLongAt: base + 13)) ] ]
		ensure: [ mem free ].
	^ rects
]

{ #category : 'ffi' }
WvShim >> frameAck [
	^ self ffiCall: #(void wv_frame_ack(void* handle)) library: WvShim libraryPath
]

{ #category : 'ffi' }
WvShim >> frameBuffer [
	^ self ffiCall: #(void* wv_frame_buffer(void* handle)) library: WvShim libraryPath
]

{ #category : 'ffi' }
WvShim >> frameHeight [
	^ self ffiCall: #(uint32 wv_frame_height(void* handle)) library: WvShim libraryPath
]

{ #category : 'frames' }
WvShim >> frameReady [
	^ self primFrameReady = 1
]

{ #category : 'ffi' }
WvShim >> frameWidth [
	^ self ffiCall: #(uint32 wv_frame_width(void* handle)) library: WvShim libraryPath
]

{ #category : 'lifecycle' }
WvShim >> isOpen [
	^ handle notNil and: [ handle isNull not ]
]

{ #category : 'ffi' }
WvShim >> loadUrl: aString [
	^ self ffiCall: #(void wv_load_url(void* handle, String aString)) library: WvShim libraryPath
]

{ #category : 'lifecycle' }
WvShim >> openExtent: aPoint [
	handle := self primCreate: aPoint x height: aPoint y.
	(handle isNil or: [ handle isNull ]) ifTrue: [ self error: 'wv_create failed' ]
]

{ #category : 'ffi - private' }
WvShim >> primCreate: w height: h [
	^ self ffiCall: #(void* wv_create(uint32 w, uint32 h)) library: WvShim libraryPath
]

{ #category : 'ffi - private' }
WvShim >> primDestroy [
	^ self ffiCall: #(void wv_destroy(void* handle)) library: WvShim libraryPath
]

{ #category : 'ffi - private' }
WvShim >> primDirtyRects: out max: maxRects [
	^ self ffiCall: #(int32 wv_frame_dirty_rects(void* handle, void* out, int32 maxRects)) library: WvShim libraryPath
]

{ #category : 'ffi - private' }
WvShim >> primFrameReady [
	^ self ffiCall: #(int32 wv_frame_ready(void* handle)) library: WvShim libraryPath
]

{ #category : 'ffi - private' }
WvShim >> primResize: w height: h [
	^ self ffiCall: #(void wv_resize(void* handle, uint32 w, uint32 h)) library: WvShim libraryPath
]

{ #category : 'lifecycle' }
WvShim >> resizeTo: aPoint [
	self isOpen ifFalse: [ ^ self ].
	self primResize: aPoint x height: aPoint y
]

{ #category : 'ffi' }
WvShim >> tick [
	^ self ffiCall: #(int32 wv_tick(void* handle)) library: WvShim libraryPath
]
