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
                WebView-Example (WebViewBrowserMorph, WebViewTabbedBrowserMorph),
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
```

The morph launches/kills its own `cef_host` process. Point the Pharo side at a
different binary with the `WV_CEF_HOST` env var or `WebViewCefMorph binaryPath:`.

## The image and the MCP bridge

- Image: `~/Documents/Pharo/images/…/Pharo14.0-browser.image` (Pharo 14).
- The image auto-resumes its `SisServer` (PharoSmalltalkInteropServer, port 8086)
  on boot; `~/Library/Preferences/pharo/startup.st` has a delayed fallback that
  starts one only if the port is free.
- Health check: `curl -m 8 -X POST localhost:8086/eval -H 'Content-Type: application/json' -d '{"code":"1+1"}'`.

## Known limitations (deferred post-v1)

- The browser texture composites **on top** of the world in its rectangle
  (world texture is XRGB8888, no alpha), so Morphs cannot overlap the browser and
  dropdowns drawn over the page are hidden. Needs alpha-hole compositing.
- IME, popup/`<select>` widgets, and a Servo backend are not implemented.
- `cef_host.app` is ad-hoc signed (local use). Distribution needs Developer ID
  signing + notarization — see `docs/DISTRIBUTION.md`.
