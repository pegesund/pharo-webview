//! wvshim — engine-agnostic browser shim with a flat C ABI.
//!
//! v1 (M2): FAKE engine — a thread renders a moving gradient at ~30 fps and
//! reports dirty rects. The host (Pharo) polls:
//!
//!   tick() -> frame_ready()? -> frame_buffer()/frame_dirty_rects() -> frame_ack()
//!
//! Threading contract: the engine paints on its own thread into a pending
//! slot; `wv_tick` (host UI thread) drains the slot into the front buffer.
//! `wv_frame_buffer` is only mutated inside `wv_tick`, so the host may read
//! it safely between ticks without locking.
//!
//! Pixel format: BGRA little-endian (== SDL_PIXELFORMAT_XRGB8888 bytes,
//! == CEF OnPaint output), row pitch = width * 4.
//!
//! Every entry point catches panics: the shim must never unwind into the VM.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

pub const WV_ABI_VERSION: u32 = 1;
const MAX_DIRTY_RECTS: usize = 64;

struct Frame {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
    dirty: Vec<[i32; 4]>, // x, y, w, h
}

struct Shared {
    pending: Mutex<Option<Frame>>,
    stop: AtomicBool,
    target_w: AtomicU32,
    target_h: AtomicU32,
}

struct Engine {
    thread: Option<JoinHandle<()>>,
    shared: Arc<Shared>,
}

pub struct WvHandle {
    front: Frame,
    ready: bool,
    engine: Engine,
}

fn fake_engine_loop(shared: Arc<Shared>) {
    let mut t: u64 = 0;
    let mut last_w = 0u32;
    let mut last_h = 0u32;
    while !shared.stop.load(Ordering::Relaxed) {
        let w = shared.target_w.load(Ordering::Relaxed);
        let h = shared.target_h.load(Ordering::Relaxed);
        if w == 0 || h == 0 {
            std::thread::sleep(std::time::Duration::from_millis(33));
            continue;
        }
        let full = w != last_w || h != last_h;
        last_w = w;
        last_h = h;

        let mut pixels = vec![0u8; (w * h * 4) as usize];
        let band_h = (h / 6).max(8);
        let band_y = ((t * 3) % (h as u64)) as u32;
        for y in 0..h {
            for x in 0..w {
                let i = ((y * w + x) * 4) as usize;
                let in_band = y >= band_y && y < band_y.saturating_add(band_h);
                let b = ((x * 255) / w.max(1)) as u8;
                let g = ((y * 255) / h.max(1)) as u8;
                let r = ((t * 2) % 255) as u8;
                if in_band {
                    pixels[i] = 255 - b; // B
                    pixels[i + 1] = 255 - g; // G
                    pixels[i + 2] = 255; // R
                } else {
                    pixels[i] = b;
                    pixels[i + 1] = g;
                    pixels[i + 2] = r;
                }
                pixels[i + 3] = 255; // X/A
            }
        }
        let dirty = if full {
            vec![[0, 0, w as i32, h as i32]]
        } else {
            // the moving band plus the band it left behind
            let prev_y = (((t - 1) * 3) % (h as u64)) as i32;
            vec![
                [0, prev_y, w as i32, band_h as i32],
                [0, band_y as i32, w as i32, band_h as i32],
                [0, 0, w as i32, 24], // fps text strip placeholder (color drift)
            ]
        };
        {
            let mut slot = shared.pending.lock().unwrap_or_else(|p| p.into_inner());
            *slot = Some(Frame {
                width: w,
                height: h,
                pixels,
                dirty,
            });
        }
        t += 1;
        std::thread::sleep(std::time::Duration::from_millis(33));
    }
}

fn handle_mut<'a>(h: *mut WvHandle) -> Option<&'a mut WvHandle> {
    if h.is_null() {
        None
    } else {
        Some(unsafe { &mut *h })
    }
}

#[no_mangle]
pub extern "C" fn wv_version() -> u32 {
    WV_ABI_VERSION
}

#[no_mangle]
pub extern "C" fn wv_create(width: u32, height: u32) -> *mut WvHandle {
    catch_unwind(|| {
        let shared = Arc::new(Shared {
            pending: Mutex::new(None),
            stop: AtomicBool::new(false),
            target_w: AtomicU32::new(width),
            target_h: AtomicU32::new(height),
        });
        let sh2 = Arc::clone(&shared);
        let thread = std::thread::Builder::new()
            .name("wvshim-fake-engine".into())
            .spawn(move || fake_engine_loop(sh2))
            .ok();
        let handle = Box::new(WvHandle {
            front: Frame {
                width,
                height,
                pixels: vec![0u8; (width * height * 4) as usize],
                dirty: Vec::new(),
            },
            ready: false,
            engine: Engine { thread, shared },
        });
        Box::into_raw(handle)
    })
    .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn wv_destroy(h: *mut WvHandle) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if h.is_null() {
            return;
        }
        let mut handle = unsafe { Box::from_raw(h) };
        handle.engine.shared.stop.store(true, Ordering::Relaxed);
        if let Some(t) = handle.engine.thread.take() {
            let _ = t.join();
        }
    }));
}

#[no_mangle]
pub extern "C" fn wv_load_url(h: *mut WvHandle, _url: *const std::os::raw::c_char) {
    // Fake engine ignores URLs. Present for ABI completeness (M3: CEF LoadURL).
    let _ = h;
}

#[no_mangle]
pub extern "C" fn wv_resize(h: *mut WvHandle, width: u32, height: u32) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(handle) = handle_mut(h) {
            handle.engine.shared.target_w.store(width, Ordering::Relaxed);
            handle.engine.shared.target_h.store(height, Ordering::Relaxed);
        }
    }));
}

/// Drain the engine's pending frame into the front buffer.
/// Returns 1 if a new frame arrived, else 0.
#[no_mangle]
pub extern "C" fn wv_tick(h: *mut WvHandle) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        let handle = match handle_mut(h) {
            Some(x) => x,
            None => return 0,
        };
        let taken = {
            let mut slot = handle
                .engine
                .shared
                .pending
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            slot.take()
        };
        if let Some(frame) = taken {
            handle.front = frame;
            handle.ready = true;
            1
        } else {
            0
        }
    }))
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn wv_frame_ready(h: *mut WvHandle) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        handle_mut(h).map(|x| if x.ready { 1 } else { 0 }).unwrap_or(0)
    }))
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn wv_frame_buffer(h: *mut WvHandle) -> *const u8 {
    catch_unwind(AssertUnwindSafe(|| {
        handle_mut(h)
            .map(|x| x.front.pixels.as_ptr())
            .unwrap_or(std::ptr::null())
    }))
    .unwrap_or(std::ptr::null())
}

#[no_mangle]
pub extern "C" fn wv_frame_width(h: *mut WvHandle) -> u32 {
    catch_unwind(AssertUnwindSafe(|| handle_mut(h).map(|x| x.front.width).unwrap_or(0))).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn wv_frame_height(h: *mut WvHandle) -> u32 {
    catch_unwind(AssertUnwindSafe(|| handle_mut(h).map(|x| x.front.height).unwrap_or(0))).unwrap_or(0)
}

/// Copy up to `max_rects` dirty rects as x,y,w,h int32 quadruples into `out`.
/// Returns the number of rects written.
#[no_mangle]
pub extern "C" fn wv_frame_dirty_rects(h: *mut WvHandle, out: *mut i32, max_rects: i32) -> i32 {
    catch_unwind(AssertUnwindSafe(|| {
        let handle = match handle_mut(h) {
            Some(x) => x,
            None => return 0,
        };
        if out.is_null() || max_rects <= 0 {
            return 0;
        }
        let n = handle
            .front
            .dirty
            .len()
            .min(max_rects as usize)
            .min(MAX_DIRTY_RECTS);
        let slice = unsafe { std::slice::from_raw_parts_mut(out, n * 4) };
        for (i, r) in handle.front.dirty.iter().take(n).enumerate() {
            slice[i * 4..i * 4 + 4].copy_from_slice(r);
        }
        n as i32
    }))
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn wv_frame_ack(h: *mut WvHandle) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if let Some(handle) = handle_mut(h) {
            handle.ready = false;
        }
    }));
}

// --- input plumbing: no-ops in the fake engine, ABI-stable for M3/M4 ---

#[no_mangle]
pub extern "C" fn wv_send_mouse_move(h: *mut WvHandle, _x: i32, _y: i32) {
    let _ = h;
}

#[no_mangle]
pub extern "C" fn wv_send_mouse_button(h: *mut WvHandle, _x: i32, _y: i32, _button: i32, _down: i32) {
    let _ = h;
}

#[no_mangle]
pub extern "C" fn wv_send_scroll(h: *mut WvHandle, _x: i32, _y: i32, _dx: i32, _dy: i32) {
    let _ = h;
}

#[no_mangle]
pub extern "C" fn wv_send_key(h: *mut WvHandle, _keycode: u32, _charcode: u32, _down: i32, _modifiers: u32) {
    let _ = h;
}
