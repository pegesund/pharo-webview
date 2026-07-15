#include "wv_client.h"

#include "include/cef_task.h"
#include "include/base/cef_bind.h"
#include "include/base/cef_callback.h"
#include "include/wrapper/cef_closure_task.h"

#include <cstdio>

static int g_pumpn = 0;
static void PumpBeginFrame(CefRefPtr<CefBrowser> browser) {
    if (!browser || !browser->GetHost()) return;
    if (g_pumpn == 0 || g_pumpn == 100)
        { std::fprintf(stderr, "[wv_host] pump n=%d\n", g_pumpn); std::fflush(stderr); }
    ++g_pumpn;
    browser->GetHost()->Invalidate(PET_VIEW);
    CefPostDelayedTask(TID_UI, base::BindOnce(&PumpBeginFrame, browser), 33);
}

WvClient::WvClient(WvShm* shm, int width, int height)
    : shm_(shm), width_(width), height_(height) {}

void WvClient::GetViewRect(CefRefPtr<CefBrowser>, CefRect& rect) {
    rect.Set(0, 0, width_.load(), height_.load());
    static int c = 0;
    if (c++ < 3) { std::fprintf(stderr, "[wv_host] GetViewRect called\n"); std::fflush(stderr); }
}

bool WvClient::GetScreenInfo(CefRefPtr<CefBrowser>, CefScreenInfo& info) {
    info.device_scale_factor = 1.0f;
    info.depth = 32;
    info.depth_per_component = 8;
    info.is_monochrome = false;
    info.rect.x = 0;
    info.rect.y = 0;
    info.rect.width = width_.load();
    info.rect.height = height_.load();
    info.available_rect = info.rect;
    return true;
}

void WvClient::OnPaint(CefRefPtr<CefBrowser>,
                       PaintElementType type,
                       const RectList& dirtyRects,
                       const void* buffer,
                       int width,
                       int height) {
    if (frame_count_ < 3) {
        std::fprintf(stderr, "[wv_host] OnPaint CALLED type=%d %dx%d\n",
                     (int)type, width, height);
        std::fflush(stderr);
    }
    if (type != PET_VIEW) return;  // ignore popup layer for v1

    int32_t dirty[WV_MAX_DIRTY * 4];
    uint32_t n = 0;
    for (const auto& r : dirtyRects) {
        if (n >= WV_MAX_DIRTY) break;
        dirty[n * 4 + 0] = r.x;
        dirty[n * 4 + 1] = r.y;
        dirty[n * 4 + 2] = r.width;
        dirty[n * 4 + 3] = r.height;
        ++n;
    }
    if (shm_) shm_->writeFrame(buffer, (uint32_t)width, (uint32_t)height, dirty, n);

    if ((frame_count_++ % 120) == 0) {
        std::fprintf(stderr, "[wv_host] OnPaint frame %llu  %dx%d  dirty=%u\n",
                     (unsigned long long)frame_count_, width, height, n);
        std::fflush(stderr);
    }
}

void WvClient::OnAcceleratedPaint(CefRefPtr<CefBrowser>,
                                  PaintElementType type,
                                  const RectList&,
                                  const CefAcceleratedPaintInfo&) {
    if (frame_count_ < 3) {
        std::fprintf(stderr, "[wv_host] OnAcceleratedPaint CALLED type=%d\n", (int)type);
        std::fflush(stderr);
    }
    ++frame_count_;
}

void WvClient::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
    if (!browser_) browser_ = browser;
    fprintf(stderr, "[wv_host] OnAfterCreated: browser id=%d, kicking paint\n",
            browser->GetIdentifier());
    fflush(stderr);
    // Kick an initial paint and make sure the view is considered visible.
    browser->GetHost()->WasHidden(false);
    browser->GetHost()->WasResized();
    browser->GetHost()->SetFocus(true);
    PumpBeginFrame(browser);
}

void WvClient::OnBeforeClose(CefRefPtr<CefBrowser>) {
    browser_ = nullptr;
}

void WvClient::OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading,
                                    bool, bool) {
    std::fprintf(stderr, "[wv_host] OnLoadingStateChange isLoading=%d\n", isLoading);
    std::fflush(stderr);
    if (!isLoading && browser) {
        browser->GetHost()->Invalidate(PET_VIEW);
        browser->GetMainFrame()->ExecuteJavaScript(
            "console.log('JS_ALIVE innerW=' + window.innerWidth + ' vis=' + document.visibilityState)",
            "wvdiag", 0);
    }
}

bool WvClient::OnConsoleMessage(CefRefPtr<CefBrowser>, cef_log_severity_t,
                                const CefString& message, const CefString&, int) {
    std::fprintf(stderr, "[wv_host] CONSOLE: %s\n", message.ToString().c_str());
    std::fflush(stderr);
    return false;
}

void WvClient::resize(int width, int height) {
    width_.store(width);
    height_.store(height);
    if (browser_) browser_->GetHost()->WasResized();
}
