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
