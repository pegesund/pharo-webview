Class {
	#name : 'WvSharedMemory',
	#superclass : 'Object',
	#instVars : [
		'path',
		'fd',
		'address',
		'size'
	],
	#category : 'WebView-FFI',
	#package : 'WebView-FFI'
}

{ #category : 'instance creation' }
WvSharedMemory class >> openPath: aPath [
	"Map the whole shared-memory file (its size is the host max capacity)."
	| ref m |
	ref := aPath asFileReference.
	ref exists ifFalse: [ ^ nil ].
	m := self new.
	(m openPath: aPath size: ref size) ifFalse: [ ^ nil ].
	^ m
]

{ #category : 'instance creation' }
WvSharedMemory class >> openPath: aPath maxWidth: w maxHeight: h [
	| m |
	m := self new.
	(m openPath: aPath size: (24 + (16*4*4) + 16) + (w * h * 4)) ifFalse: [ ^ nil ].
	^ m
]

{ #category : 'header' }
WvSharedMemory >> alive [ ^ (self u32At: (24 + (16*4*4) + 8)) = 1
]

{ #category : 'lifecycle' }
WvSharedMemory >> close [
	address ifNotNil: [ self primMunmap: address len: size ]. address := nil.
	fd ifNotNil: [ self primClose: fd ]. fd := nil
]

{ #category : 'header' }
WvSharedMemory >> dirtyRects [
	"Read up to num_dirty dirty rects (x,y,w,h int32 quads starting at byte 24)
	as Rectangles. Caller must decide whether they are safe to use (no skipped seq)."
	| n rects |
	self isValid ifFalse: [ ^ #() ].
	n := self numDirty min: 16.
	rects := OrderedCollection new.
	1 to: n do: [ :i | | base x y w h |
		base := 24 + ((i - 1) * 16).
		x := address signedLongAt: base + 1.
		y := address signedLongAt: base + 5.
		w := address signedLongAt: base + 9.
		h := address signedLongAt: base + 13.
		(w > 0 and: [ h > 0 ]) ifTrue: [ rects add: (x @ y extent: w @ h) ] ].
	^ rects
]

{ #category : 'ffi' }
WvSharedMemory >> ffiLibraryName [
	^ 'libc.dylib'
]

{ #category : 'header' }
WvSharedMemory >> height [ ^ self u32At: 12
]

{ #category : 'lifecycle' }
WvSharedMemory >> isOpen [
	^ address notNil and: [ address isNull not ]
]

{ #category : 'header' }
WvSharedMemory >> isValid [
	^ self isOpen and: [ self magic = 16r57565348 ]
]

{ #category : 'header' }
WvSharedMemory >> magic [ ^ self u32At: 0
]

{ #category : 'header' }
WvSharedMemory >> numDirty [ ^ self u32At: 20
]

{ #category : 'lifecycle' }
WvSharedMemory >> openPath: aPath size: aSize [
	"Map the shared-memory file read-only. Returns true on success."
	| oRDONLY protRead mapShared |
	path := aPath. size := aSize.
	oRDONLY := 0. protRead := 1. mapShared := 1.
	fd := self primOpen: aPath flags: oRDONLY.
	fd < 0 ifTrue: [ ^ false ].
	address := self primMmapLen: aSize prot: protRead flags: mapShared fd: fd offset: 0.
	(address isNil or: [ address isNull ]) ifTrue: [ self primClose: fd. fd := nil. ^ false ].
	^ true
]

{ #category : 'header' }
WvSharedMemory >> pixelsAddress [
	"ExternalAddress of the BGRA pixel region (== XRGB8888 bytes for SDL)."
	^ address + self pixelsOffset
]

{ #category : 'header' }
WvSharedMemory >> pixelsOffset [ ^ self u32At: (24 + (16 * 4 * 4))
]

{ #category : 'header' }
WvSharedMemory >> pixelCapacityBytes [
	"Bytes actually available in the mapped pixel region: total mapping minus the
	 header/pixel offset. A frame copy must never exceed this, or a garbage width/
	 height left in the header by a host that crashed mid-write would drive an FFI
	 memcpy past the mapping and segfault the whole image."
	| off |
	(size isNil or: [ address isNil ]) ifTrue: [ ^ 0 ].
	off := self pixelsOffset.
	(off < 24 or: [ off > size ]) ifTrue: [ ^ 0 ].
	^ size - off
]

{ #category : 'header' }
WvSharedMemory >> safeFrameExtent [
	"width@height ONLY if the header is self-consistent and the frame fits inside the
	 mapped region; otherwise nil. Every FFI read of the pixel buffer must gate on this:
	 a host that died mid-write can leave valid magic but a half-written / garbage
	 width, height or seq, and copying that many bytes would crash the entire Pharo
	 image (not just the webview). seq odd = write in progress, so skip that frame too."
	| w h |
	self isValid ifFalse: [ ^ nil ].
	self seq odd ifTrue: [ ^ nil ].
	w := self width. h := self height.
	((w between: 1 and: 8192) and: [ h between: 1 and: 8192 ]) ifFalse: [ ^ nil ].
	(w * h * 4) > self pixelCapacityBytes ifTrue: [ ^ nil ].
	^ w @ h
]

{ #category : 'ffi' }
WvSharedMemory >> primClose: fdInt [
	^ self ffiCall: #(int close(int fdInt))
]

{ #category : 'ffi' }
WvSharedMemory >> primMmapLen: lengthInt prot: protInt flags: flagsInt fd: fdInt offset: offsetInt [
	^ self ffiCall: #(void* mmap(nil, size_t lengthInt, int protInt, int flagsInt, int fdInt, size_t offsetInt))
]

{ #category : 'ffi' }
WvSharedMemory >> primMunmap: addr len: lengthInt [
	^ self ffiCall: #(int munmap(void* addr, size_t lengthInt))
]

{ #category : 'ffi' }
WvSharedMemory >> primOpen: aPath flags: flagsInt [
	^ self ffiCall: #(int open(String aPath, int flagsInt))
]

{ #category : 'header' }
WvSharedMemory >> seq [ ^ self u32At: 16
]

{ #category : 'accessing' }
WvSharedMemory >> u32At: byteOffset [
	"Read a little-endian uint32 at the given 0-based byte offset."
	^ address unsignedLongAt: byteOffset + 1
]

{ #category : 'header' }
WvSharedMemory >> width [ ^ self u32At: 8
]
