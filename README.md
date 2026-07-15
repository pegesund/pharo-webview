# pharo-webview

A browser engine composited into the Pharo Morphic world — GPU-composited at the
SDL present step, no per-frame copy into the world Form.

The full plan and live milestone status live **in the image** as
`WebViewProjectPlan` (package `WebView-Planning`):
`WebViewProjectPlan planMarkdown`, `WebViewProjectPlan statusString`,
`WebViewProjectPlan reportAt: #M0` … `#M3`.

## Status

| Milestone | State | What it proves |
|-----------|-------|----------------|
| M0 Rig proof | ✅ done | Findings 1–5 verified against the live Pharo 14 image |
| M1 Texture proof | ✅ done | Animated Pharo-side buffer GPU-composited over the world (`docs/m1-verification.png`) |
| M2 Shim skeleton | ✅ done | Rust cdylib + fake engine behind a flat C ABI, driven over uFFI (`docs/m2-verification.png`) |
| M3 Real browser | 🟡 goal met via CDP backend; in-process CEF OSR pending | **Real Chrome page rendered live in a morph** (`docs/m3-*.png`) |
| M4 Input | ⬜ todo | |
| M5 Lifecycle & polish | ⬜ todo | |

## Layout

```
src/                Tonel export of the Pharo packages (WebView-Core, -FFI, -Planning, -Tests)
shim/               Rust cdylib (wvshim): flat C ABI, engine behind a trait; M2 fake engine
cdp/                chrome-screencast.mjs — headless-Chrome CDP screencast helper (M3, zero deps)
                    demo-live.html — animated page used to prove live rendering
docs/               milestone verification screenshots
scripts/            restart-image.sh — relaunch the Pharo image (auto-restarts the MCP server)
```

## The image and the MCP bridge

- Image: `~/Documents/Pharo/images/…/Pharo14.0-browser.image` (Pharo 14).
- The image auto-resumes its `SisServer` (PharoSmalltalkInteropServer, port 8086)
  on boot. `~/Library/Preferences/pharo/startup.st` adds a delayed fallback that
  starts one only if the port is free (double-start = "Address already in use").
- Health check: `curl -m 8 -X POST localhost:8086/eval -H 'Content-Type: application/json' -d '{"code":"1+1"}'`.

## M3 backends

The engine-agnostic design allows interchangeable real-browser frame sources:

- **CDP screencast (implemented):** Chrome `--headless=new` → DevTools
  `Page.startScreencast` (PNG) → `cdp/chrome-screencast.mjs` writes frames →
  `WebViewCdpMorph` decodes and pushes them through the M1 overlay path.
  Run: `node cdp/chrome-screencast.mjs <url> /tmp/wv-cdp 800 600`.
- **In-process CEF OSR (target, pending):** `OnPaint` → BGRA + dirty rects into
  the `wvshim` ABI, no decode. See `WebViewProjectPlan reportAt: #M3` for the
  remaining work (framework bundle, helper subprocess, codesigning, message pump).
