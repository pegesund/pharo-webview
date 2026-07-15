# pharo-webview

A real web browser (Chromium, via CEF) running **as a Morphic morph** in Pharo —
GPU-composited at the SDL present step, with raw BGRA frames over shared memory
(no PNG, no per-frame decode). Mouse, keyboard, resize, navigation, multiple
simultaneous browsers, and a tabbed browser example all work.

The full plan and live milestone status live **in the image** as
`WebViewProjectPlan` (package `WebView-Planning`):
`WebViewProjectPlan planMarkdown`, `WebViewProjectPlan statusString`,
`WebViewProjectPlan reportAt: #M3CEF` (etc.).

## Status — all milestones done

| Milestone | What it delivered |
|-----------|-------------------|
| M0 Rig proof | Renderer/present internals verified against the live Pharo 14 image |
| M1 Texture proof | Pharo-side buffer GPU-composited over the world at the present step |
| M2 Shim skeleton | Rust cdylib + fake engine behind a flat C ABI, driven over uFFI |
| M3 Real browser | **In-process CEF (OSR) rendered live in a morph** via raw-BGRA shared memory (`docs/m3-cef-in-morph.png`). A CDP-screencast backend also exists as a fallback. |
| M4 Input | Mouse click/move/scroll + keyboard routed morph → CEF (`docs/m4-cef-click.png`) |
| M5 Lifecycle & polish | Process lifecycle, resize, focus, **multiple simultaneous browsers**, a **tabbed browser** example, dirty-rect uploads, distribution scripts |

## Architecture (CEF backend)

```
WebViewCefMorph (Morphic)  ── owns ──►  cef_host.app (separate process)
   │  reads frames                          │  CEF windowless/OSR
   │                                        │  OnPaint → raw BGRA + dirty rects
   ▼                                        ▼
WvSharedMemory (uFFI mmap) ◄── POSIX shared-memory file ──  WvShm writer
   │  ExternalAddress
   ▼
WebViewFormRenderer (OSSDL2FormRenderer subclass, priority 3)
   multi-overlay: one texture per webview, composited in z-order before present
   ▲  input: morph events → input.jsonl → WvControl → CEF Send*Event / navigation
```

Why this shape (all hard-won — see `WebViewProjectPlan reportAt: #M3CEF`):
- **Separate process**, not in-process CEF: macOS bundle/threading/crash-isolation.
- CEF command line that actually renders headless on macOS:
  `--in-process-gpu --disable-gpu-sandbox --single-process --use-mock-keychain
  --password-store=basic` (the missing `--single-process` was the unlock — the
  renderer subprocess never spawned otherwise).

## Layout

```
src/            Tonel export of the Pharo packages:
                WebView-Core (morphs + renderer), WebView-FFI (WvShim, WvSharedMemory),
                WebView-Example (WebViewBrowserMorph, WebViewTabbedBrowserMorph, WebViewMenuBrowserMorph),
                WebView-Planning, WebView-Core-Tests
cef_host/       The CEF host app (C++): CefRenderHandler → shared memory, input channel,
                navigation. third_party/cef holds the CEF distribution (fetched, gitignored).
shim/           Rust cdylib (wvshim): flat C ABI, fake engine (M2 stepping stone)
cdp/            chrome-screencast.mjs — headless-Chrome CDP fallback backend; demo pages
docs/           milestone verification screenshots; DISTRIBUTION.md
scripts/        fetch-cef.sh, build-cef-host.sh, restart-image.sh
```

## Build & run

```bash
scripts/fetch-cef.sh        # download the pinned CEF distribution
scripts/build-cef-host.sh   # build + ad-hoc sign cef_host.app
```

Then in Pharo (packages loaded from `src/`):

```smalltalk
WebViewFormRenderer install.                      "activate the compositing renderer"
WebViewBrowserMorph new openInWorld.              "a browser widget (toolbar + address bar)"
WebViewTabbedBrowserMorph new openInWorld.        "a tabbed multi-view browser"
WebViewMenuBrowserMorph open.                     "a 'Steder' dropdown menu that overlays the page (z-order demo)"
```

The morph launches/kills its own `cef_host` process. Point the Pharo side at a
different binary with the `WV_CEF_HOST` env var or `WebViewCefMorph binaryPath:`.

## The image and the MCP bridge

- Image: `~/Documents/Pharo/images/…/Pharo14.0-browser.image` (Pharo 14).
- The image auto-resumes its `SisServer` (PharoSmalltalkInteropServer, port 8086)
  on boot; `~/Library/Preferences/pharo/startup.st` has a delayed fallback that
  starts one only if the port is free.
- Health check: `curl -m 8 -X POST localhost:8086/eval -H 'Content-Type: application/json' -d '{"code":"1+1"}'`.

## Running JavaScript & manipulating the DOM from Pharo

`WebViewCefMorph` can push JavaScript into the page (an `eval` command over the
input channel → `CefFrame::ExecuteJavaScript` in the main frame):

```smalltalk
"fire-and-forget — mutate the DOM"
webview evalJs: 'document.body.style.background = "#ffe000"'.
webview evalJs: 'document.querySelector("h1").textContent = "Hei fra Pharo"'.

"expression → value back in Pharo (via the window.pharo bridge, on the UI process)"
webview evalJs: '2 + 40'                          then: [ :r | r "=> 42" ].
webview evalJs: 'document.title'                  then: [ :r | r "=> a String" ].
webview evalJs: 'JSON.parse(localStorage.foo||"{}")' then: [ :r | r "=> a Dictionary" ].

"multiple statements: use a function expression that returns"
webview
  evalJs: '(function(){ document.body.insertAdjacentHTML("afterbegin","<h2>hi</h2>");
                        return document.querySelectorAll("h2").length })()'
  then: [ :n | n "=> the count" ].
```

`evalJs:then:` wraps the expression, ships its result through
`window.pharo.emit('__eval', …)`, and delivers it to the block; JS numbers,
strings, booleans, arrays and objects arrive as the matching Pharo objects
(objects → `Dictionary`). A JS exception is caught and logged. Values must be
JSON-able. Because commands are JSON-escaped, the JS may contain quotes, braces
and newlines freely.

## Events & JS ↔ Pharo callbacks

`cef_host` writes a reverse event channel (`<control>.events`, one JSON object per
line); `WebViewCefMorph` tails it in its step loop and dispatches to blocks you
register. Lifecycle events come from CEF's load/display handlers; a
`window.pharo.emit(name, data)` bridge (injected into every V8 context before page
scripts) lets page JavaScript push structured data to Pharo.

```smalltalk
webview onPageLoad:    [ :e | Transcript showln: 'loaded ', (e at: 'url') ].
webview onTitleChange: [ :e | Transcript showln: (e at: 'title') ].
webview onLoadError:   [ :e | Transcript showln: 'error ', (e at: 'errorText') ].
webview onJs:          [ :e | inspect: (e at: 'data') ].          "any emit()"
webview onJs: 'cart'   do: [ :e | updateCart: (e at: 'data') ].   "emit('cart', …)"
"generic:  webview onEvent: #loadEnd do: [ :e | … ]"
```

```js
// in the page:
window.pharo.emit('cart', { items: 3, total: 49.9 });   // -> arrives as a Dictionary
```

Event kinds: `loadStart`, `loadEnd` (`url`, `httpStatus`), `loadingState`
(`isLoading`, `canGoBack`, `canGoForward`), `loadError`, `title`, and `js`
(`name`, `data`). The block arg is the parsed event `Dictionary`; callbacks run on
the UI process, wrapped so one failing block can't break stepping.
`WebViewMenuBrowserMorph` shows the live page title in its bar via `onTitleChange:`.

## Z-order (Morphs over the browser)

The browser texture composites on top of the world in its rectangle, but it is
**occlusion-clipped to the live Morphic z-order**: before each present, the
renderer subtracts the device rectangles of any morph in front of the browser
morph (at any ancestor level) from the browser's bounds, and copies the CEF
texture only into the remaining pieces (`WebViewFormRenderer>>occludersFor:target:`
+ `drawOverlayOccluded:`). So a Morph placed over the browser appears on top of
the page, and bringing the browser `comeToFront` covers the Morph again — z-order
is respected every frame.

This replaced an earlier attempt at alpha-hole compositing (world texture as
ARGB8888 + a punched transparent hole): on this macOS/Metal SDL backend an
ARGB8888 streaming texture uploaded from the Pharo world Form rendered
transparent regardless of the Form's opaque alpha, so the occlusion-clipping
route (which keeps the known-good XRGB8888 world texture) is used instead.

## Known limitations (deferred post-v1)

- Occlusion is rectangular: a morph in front clips the browser by its bounding
  box, so non-rectangular / rounded morphs occlude a slightly larger rectangle.
- IME, popup/`<select>` widgets, and a Servo backend are not implemented.
- `cef_host.app` is ad-hoc signed (local use). Distribution needs Developer ID
  signing + notarization — see `docs/DISTRIBUTION.md`.
