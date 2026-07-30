"
Platform dispatch for the cef_host bridge: temp-file locations, detached
process launch, pid liveness and termination.

macOS/Linux keep the original shell-based paths (/tmp + sh + ps/kill).
Windows uses kernel32 FFI directly -- CreateProcessA with bInheritHandles=FALSE
(which also solves the fd-inheritance problem the mac side needs a perl
wrapper for), OpenProcess/GetExitCodeProcess for liveness, TerminateProcess
for kill. No console window ever flashes.
"
Class {
	#name : 'WvPlatform',
	#superclass : 'Object',
	#category : 'WebView-Core',
	#package : 'WebView-Core'
}

{ #category : 'testing' }
WvPlatform class >> isWindows [
	^ OSPlatform current isWindows
]

{ #category : 'display' }
WvPlatform class >> displayScale [
	"OS display scale (1.0 = 100%). Windows: system DPI / 96 (the VM is DPI-aware,
	 so windows are physical pixels). Elsewhere 1.0 -- macOS retina is handled by
	 the window system. Cached; clamped to [1, 3]."
	^ Smalltalk at: #WvDisplayScale ifAbsent: [
		| f |
		f := 1.0.
		self isWindows ifTrue: [
			f := ([ (self primGetDpiForSystem / 96.0) max: 1.0 ] on: Error do: [ :e | 1.0 ]) min: 3.0 ].
		Smalltalk at: #WvDisplayScale put: f.
		f ]
]

{ #category : 'display' }
WvPlatform class >> primGetDpiForSystem [
	"System DPI (96 = 100%). Windows 10+."
	^ self ffiCall: #(uint32 GetDpiForSystem()) library: 'user32.dll'
]

{ #category : 'paths' }
WvPlatform class >> tmpFileNamed: aString [
	"Full path for a bridge temp file (shm, input, pid, log)."
	self isWindows ifTrue: [ ^ (FileLocator temp asFileReference / aString) fullName ].
	^ '/tmp/', aString
]

{ #category : 'process - windows ffi' }
WvPlatform class >> primCreateProcess: cmdline inherit: inheritInt flags: flags si: si pi: pi [
	"CreateProcessA(NULL, cmdline, NULL, NULL, inherit, flags, NULL, NULL, &si, &pi).
	 bInheritHandles=FALSE: the child gets no image fds/sockets."
	^ self ffiCall: #(int CreateProcessA(nil, String cmdline, nil, nil, int inheritInt, uint32 flags, nil, nil, void* si, void* pi)) library: 'kernel32.dll'
]

{ #category : 'process - windows ffi' }
WvPlatform class >> primOpenProcess: access inherit: inheritInt pid: pid [
	^ self ffiCall: #(void* OpenProcess(uint32 access, int inheritInt, uint32 pid)) library: 'kernel32.dll'
]

{ #category : 'process - windows ffi' }
WvPlatform class >> primGetExitCode: handle into: buf [
	^ self ffiCall: #(int GetExitCodeProcess(void* handle, void* buf)) library: 'kernel32.dll'
]

{ #category : 'process - windows ffi' }
WvPlatform class >> primTerminateProcess: handle code: codeInt [
	^ self ffiCall: #(int TerminateProcess(void* handle, uint32 codeInt)) library: 'kernel32.dll'
]

{ #category : 'process - windows ffi' }
WvPlatform class >> primCloseHandle: handle [
	^ self ffiCall: #(int CloseHandle(void* handle)) library: 'kernel32.dll'
]

{ #category : 'process' }
WvPlatform class >> launchDetached: exePath arguments: argStrings pidFile: pidPathOrNil [
	"Start exePath with argStrings, fully detached (no inherited handles, no console
	 window). Answers the child pid (Integer) or nil. Windows-only; POSIX callers
	 keep their shell-based launch."
	| cmdline si pi ok pid |
	self isWindows ifFalse: [ ^ nil ].
	cmdline := String streamContents: [ :s |
		s nextPut: $"; nextPutAll: exePath; nextPut: $".
		argStrings do: [ :a | s space; nextPut: $"; nextPutAll: a asString; nextPut: $" ] ].
	"STARTUPINFOA is 104 bytes on x64 (cb first); PROCESS_INFORMATION is 24."
	si := ByteArray new: 104.
	si unsignedLongAt: 1 put: 104.
	pi := ByteArray new: 24.
	"CREATE_NO_WINDOW (16r08000000): a GUI child ignores it; a console child gets no window."
	ok := self primCreateProcess: cmdline inherit: 0 flags: 16r08000000 si: si pi: pi.
	ok = 0 ifTrue: [ ^ nil ].
	pid := pi unsignedLongAt: 17.  "dwProcessId after the two 8-byte handles"
	self primCloseHandle: (pi pointerAt: 1).
	self primCloseHandle: (pi pointerAt: 9).
	pidPathOrNil ifNotNil: [
		[ pidPathOrNil asFileReference
			writeStreamDo: [ :ws | ws nextPutAll: pid printString ] ] on: Error do: [ :e | ] ].
	^ pid
]

{ #category : 'process' }
WvPlatform class >> isPidAlive: pidStringOrInt [
	"true if the OS process is still running."
	| pid h buf alive |
	pid := pidStringOrInt asString trimBoth.
	pid isEmpty ifTrue: [ ^ false ].
	pid := [ pid asNumber asInteger ] on: Error do: [ :e | ^ false ].
	(pid isNil or: [ pid <= 0 ]) ifTrue: [ ^ false ].
	self isWindows ifFalse: [
		^ ([ LibC uniqueInstance runCommand: 'ps -p ', pid printString, ' >/dev/null 2>&1' ]
			on: Error do: [ :e | 256 ]) = 0 ].
	"PROCESS_QUERY_LIMITED_INFORMATION = 16r1000"
	h := self primOpenProcess: 16r1000 inherit: 0 pid: pid.
	(h isNil or: [ h isNull ]) ifTrue: [ ^ false ].
	buf := ByteArray new: 4.
	alive := (self primGetExitCode: h into: buf) ~= 0
		and: [ (buf unsignedLongAt: 1) = 259 ].  "STILL_ACTIVE"
	self primCloseHandle: h.
	^ alive
]

{ #category : 'process' }
WvPlatform class >> terminatePid: pidStringOrInt [
	| pid h |
	pid := [ pidStringOrInt asString trimBoth asNumber asInteger ] on: Error do: [ :e | nil ].
	(pid isNil or: [ pid <= 0 ]) ifTrue: [ ^ self ].
	self isWindows ifFalse: [
		[ LibC runCommand: 'kill ', pid printString, ' 2>/dev/null' ] on: Error do: [ :e | ].
		^ self ].
	"PROCESS_TERMINATE = 1"
	h := self primOpenProcess: 1 inherit: 0 pid: pid.
	(h isNil or: [ h isNull ]) ifTrue: [ ^ self ].
	self primTerminateProcess: h code: 1.
	self primCloseHandle: h
]
