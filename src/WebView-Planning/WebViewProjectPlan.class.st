"
Project plan and live execution status for the browser-engine-in-Morphic project: a WebViewMorph showing live web content (CEF in OSR mode behind a Rust shim), GPU-composited at the SDL present step.

Class-side API:
  planMarkdown  - the full plan as markdown
  status        - Dictionary milestone -> #todo / #inProgress / #done
  markDone: / markInProgress: - update status
  reportAt: / addReport:text: - milestone deliverable reports (e.g. M0 discrepancy report)
"
Class {
	#name : 'WebViewProjectPlan',
	#superclass : 'Object',
	#classVars : [
		'MilestoneStatus',
		'Reports'
	],
	#category : 'WebView-Planning',
	#package : 'WebView-Planning'
}

{ #category : 'accessing' }
WebViewProjectPlan class >> addReport: aSymbol text: aString [
	self reports at: aSymbol put: aString
]

{ #category : 'initialization' }
WebViewProjectPlan class >> initialize [
	"WebViewProjectPlan initialize"
	MilestoneStatus := Dictionary new.
	#(M0 M1 M2 M3 M4 M5) do: [ :m | MilestoneStatus at: m put: #todo ].
	Reports := Dictionary new
]

{ #category : 'logging' }
WebViewProjectPlan class >> log: aString [
	(Smalltalk at: #WvLog ifAbsentPut: [ OrderedCollection new ])
		add: DateAndTime now printString, ' | ', aString
]

{ #category : 'logging' }
WebViewProjectPlan class >> logContents [
	^ (Smalltalk at: #WvLog ifAbsent: [ #() ]) asArray joinUsing: String cr
]

{ #category : 'accessing' }
WebViewProjectPlan class >> markDone: aSymbol [
	self status at: aSymbol put: #done
]

{ #category : 'accessing' }
WebViewProjectPlan class >> markInProgress: aSymbol [
	self status at: aSymbol put: #inProgress
]

{ #category : 'plan' }
WebViewProjectPlan class >> planMarkdown [
	"The full project plan, verbatim, as markdown."
	^ '# PLAN - browser engine composited into the Pharo world

## Goal

A `WebViewMorph` that displays live web content (HTML + JS is the priority;
video is secondary) inside the standard Morphic world, GPU-composited at the
SDL present step - no per-frame copy into the world Form.

## Decisions already made

- **Engine: CEF first**, in offscreen rendering (OSR) mode with dirty rects.
  Full web compatibility; the risk budget goes to integration, not the engine.
- **Engine-agnostic Rust shim** with a flat C ABI so a Servo backend can be
  added later behind a feature flag without touching Smalltalk.
- **Compositing strategy: interleave at the SDL present step** ("hijack the
  presentation step"), not blitting into the world Form and not a native
  child window.
- v1 limitation accepted: the browser texture is composited ON TOP of the
  world in its rectangle (world texture is XRGB8888, no alpha). Morphs
  cannot overlap the browser in v1.

## Verified findings from the Pharo source (pharo-project/pharo, July 2026)

These were confirmed by reading the actual code - treat as ground truth,
but re-verify in the image if something behaves differently:

1. **Renderer selection is a pluggable registry.**
   `AbstractWorldRenderer class>>detectCorrectOneForWorld:` picks among
   `allSubclasses` sorted by class-side `priority`, first where
   `isApplicableFor:` is true. `OSWorldRenderer` has priority 2 - our
   subclass returns 3 and wins automatically. No patching.
2. **The present path** is:
   `displayWorldState:ofWorld:` (damage rects) ->
   `OSWorldRenderer>>updateDamage:` ->
   `OSSDL2FormRenderer>>updateAreas:immediate:` -> lock streaming texture,
   copy dirty rects from the world Form, then
   `renderer copy: texture. renderer present.`
   The interleave points are `copyAndPresentTextureRectangle:` and
   `useDeferredUpdates`.
3. **SDL2 bindings already expose what we need** (`OSWindow-SDL2` package):
   `SDL_UpdateTexture` full + per-rect, `SDL_LockTexture`,
   `copy:srcRect:dstRect:`, `SDL_SetTextureBlendMode`. The browser gets its
   OWN streaming texture; CEF''s BGRA buffer is uploaded with dirty rects and
   the GPU composites. No BitBlt, no readback.
4. **World texture is `SDL_PIXELFORMAT_XRGB8888`** (no alpha) - hence the
   v1 overlay limitation. "Browser under world through an alpha hole" needs
   ARGB8888 + blend mode + a morph that writes alpha 0. Post-v1.
5. **Frame pacing**: `WorldState MinCycleLapse = 16` ms (60 fps ceiling),
   damage-driven. Default renderer flags are 0 (vsync only added on macOS).
   `OSSDL2FormRenderer` guards everything with a Mutex - respect it.

## Architecture

WebViewMorph        placeholder: geometry, input, focus
WebViewFormRenderer OSSDL2FormRenderer subclass: owns {texture, bounds} per
                    webview, interleaves copies before present
WebViewWorldRenderer OSWorldRenderer subclass, prio 3
WebView-FFI         uFFI bindings to the shim ABI
shim/ (Rust, cdylib) flat C ABI, engine behind a trait:
  wv_create(w,h) wv_destroy wv_load_url wv_tick
  wv_send_mouse wv_send_key wv_send_scroll wv_resize
  wv_set_paint_callback(buffer, dirty_rects, n)
CEF in OSR mode: OnPaint -> BGRA + dirty rects

Data flow per frame: CEF paints on its thread -> shim stores buffer + rects,
flips a flag -> Morphic cycle (UI process) sees the flag ->
`SDL_UpdateTexture` per dirty rect -> present interleaves world texture then
browser texture (dstRect = morph bounds).

## Milestones

Each milestone ends with tests green, `read_screen` verification where
rendering is involved, and an Iceberg/git commit.

- **M0 - Rig proof.** Via MCP: read `AbstractWorldRenderer` and
  `OSSDL2FormRenderer` in the live image and confirm findings 1-5 above
  hold in Petter''s image/version. Deliverable: short discrepancy report.
- **M1 - Texture proof, no engine.** `WebViewWorldRenderer` +
  `WebViewFormRenderer` compositing a procedurally generated test-pattern
  texture (animated, from a Pharo-side buffer) over the world at a fixed
  rect. Proves the whole interleave without any FFI.
- **M2 - Shim skeleton.** Rust cdylib with the ABI above and a FAKE engine
  (renders a moving gradient + reports dirty rects). uFFI bindings.
  The M1 test pattern is replaced by the shim''s buffer. Proves FFI,
  threading handoff, and dirty-rect upload.
- **M3 - CEF behind the shim.** Real CEF in OSR mode replaces the fake
  engine. Static page renders in the morph. Message-loop pump wired into
  the Morphic cycle. Distribution notes for the CEF bundle on macOS.
- **M4 - Input.** Mouse move/click/wheel and keyboard routed from
  WebViewMorph through the shim. Acceptance: type into a text field on a
  real page; scroll a long page.
- **M5 - Lifecycle & polish.** Resize, morph open/close/GC -> engine
  teardown, multiple simultaneous webviews, focus handling. Known
  deferred items: IME, popup widgets (select dropdowns), alpha-hole
  compositing, Servo backend experiment.

## Risks / watchpoints

- Metacello/Iceberg loading quirks (already bitten once: silent no-op load;
  fix was manual Iceberg load + `MCGitHubRepository flushDownloadCache`).
- CEF distribution on macOS: framework bundle layout, subprocess helper
  apps, codesigning. Budget real time for this in M3.
- Everything in the threading section of CLAUDE.md.
' 
]

{ #category : 'accessing' }
WebViewProjectPlan class >> reportAt: aSymbol [
	^ self reports at: aSymbol ifAbsent: [ nil ]
]

{ #category : 'accessing' }
WebViewProjectPlan class >> reports [
	Reports ifNil: [ self initialize ].
	^ Reports
]

{ #category : 'accessing' }
WebViewProjectPlan class >> status [
	MilestoneStatus ifNil: [ self initialize ].
	^ MilestoneStatus
]

{ #category : 'accessing' }
WebViewProjectPlan class >> statusString [
	^ String streamContents: [ :s |
		#(M0 M1 M2 M3 M4 M5)
			do: [ :m | s nextPutAll: m asString; nextPutAll: ': '; nextPutAll: (self status at: m) asString ]
			separatedBy: [ s cr ] ]
]
