#include "wv_client.h"

#include "include/cef_task.h"
#include "include/cef_frame.h"
#include "include/cef_parser.h"
#include "include/cef_values.h"
#include "include/base/cef_bind.h"
#include "include/base/cef_callback.h"
#include "include/wrapper/cef_closure_task.h"

#include <cstdio>
#include <cstring>

// JS-side bridge injected on every main-frame load: window.pharo.emit(name, data)
// logs a tagged console line that OnConsoleMessage forwards to the events file.
static const char* kPharoBridgeJS =
    "window.pharo=window.pharo||{emit:function(n,d){try{"
    "console.log('__PHARO__'+JSON.stringify({event:'js',name:n,"
    "data:(d===undefined?null:d)}));}catch(e){}}};";
static const char* kPharoTag = "__PHARO__";

// Headless single-process CEF has no vsync/display begin-frame source, so drive
// repaints ourselves: invalidate the view on a timer and OnPaint follows.
static void PumpBeginFrame(CefRefPtr<CefBrowser> browser) {
    if (!browser || !browser->GetHost()) return;
    browser->GetHost()->Invalidate(PET_VIEW);
    CefPostDelayedTask(TID_UI, base::BindOnce(&PumpBeginFrame, browser), 33);
}

WvClient::WvClient(WvShm* shm, int width, int height)
    : shm_(shm), width_(width), height_(height) {}

void WvClient::GetViewRect(CefRefPtr<CefBrowser>, CefRect& rect) {
    rect.Set(0, 0, width_.load(), height_.load());
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
    ++frame_count_;
}

void WvClient::OnAcceleratedPaint(CefRefPtr<CefBrowser>,
                                  PaintElementType,
                                  const RectList&,
                                  const CefAcceleratedPaintInfo&) {
    // Unused: single-process software OSR delivers CPU OnPaint, not this path.
}

void WvClient::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
    if (!browser_) browser_ = browser;
    browser->GetHost()->WasHidden(false);
    browser->GetHost()->WasResized();
    browser->GetHost()->SetFocus(true);
    PumpBeginFrame(browser);  // start driving repaints
}

void WvClient::OnBeforeClose(CefRefPtr<CefBrowser>) {
    browser_ = nullptr;
}

void WvClient::appendEventLine(const std::string& jsonLine) {
    if (events_path_.empty()) return;
    if (FILE* f = std::fopen(events_path_.c_str(), "a")) {
        std::fwrite(jsonLine.data(), 1, jsonLine.size(), f);
        std::fputc('\n', f);
        std::fclose(f);
    }
}

void WvClient::emitEvent(CefRefPtr<CefDictionaryValue> d) {
    if (events_path_.empty() || !d) return;
    CefRefPtr<CefValue> v = CefValue::Create();
    v->SetDictionary(d);
    appendEventLine(CefWriteJSON(v, JSON_WRITER_DEFAULT).ToString());
}

void WvClient::OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading,
                                    bool canGoBack, bool canGoForward) {
    if (!isLoading && browser) {
        browser->GetHost()->Invalidate(PET_VIEW);
    }
    CefRefPtr<CefDictionaryValue> d = CefDictionaryValue::Create();
    d->SetString("event", "loadingState");
    d->SetBool("isLoading", isLoading);
    d->SetBool("canGoBack", canGoBack);
    d->SetBool("canGoForward", canGoForward);
    emitEvent(d);
}

void WvClient::OnLoadStart(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                           TransitionType) {
    if (!frame || !frame->IsMain()) return;
    // Install the JS bridge early so page scripts can call window.pharo.emit().
    frame->ExecuteJavaScript(kPharoBridgeJS, frame->GetURL(), 0);
    CefRefPtr<CefDictionaryValue> d = CefDictionaryValue::Create();
    d->SetString("event", "loadStart");
    d->SetString("url", frame->GetURL());
    emitEvent(d);
}

void WvClient::OnLoadEnd(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                         int httpStatusCode) {
    if (!frame || !frame->IsMain()) return;
    CefRefPtr<CefDictionaryValue> d = CefDictionaryValue::Create();
    d->SetString("event", "loadEnd");
    d->SetString("url", frame->GetURL());
    d->SetInt("httpStatus", httpStatusCode);
    emitEvent(d);
}

void WvClient::OnLoadError(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                           ErrorCode errorCode, const CefString& errorText,
                           const CefString& failedUrl) {
    if (frame && !frame->IsMain()) return;
    CefRefPtr<CefDictionaryValue> d = CefDictionaryValue::Create();
    d->SetString("event", "loadError");
    d->SetInt("errorCode", errorCode);
    d->SetString("errorText", errorText);
    d->SetString("url", failedUrl);
    emitEvent(d);
}

void WvClient::OnTitleChange(CefRefPtr<CefBrowser>, const CefString& title) {
    CefRefPtr<CefDictionaryValue> d = CefDictionaryValue::Create();
    d->SetString("event", "title");
    d->SetString("title", title);
    emitEvent(d);
}

bool WvClient::OnConsoleMessage(CefRefPtr<CefBrowser>, cef_log_severity_t,
                                const CefString& message, const CefString&, int) {
    std::string m = message.ToString();
    if (m.rfind(kPharoTag, 0) == 0) {  // starts with the bridge tag
        appendEventLine(m.substr(std::strlen(kPharoTag)));  // remainder is JSON
        return true;  // handled: suppress default console logging
    }
    return false;
}

void WvClient::OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                               const CefString& url) {
    // Only the main frame's address; write it to the status file (best-effort)
    // so the Pharo address bar can reflect redirects and clicked links.
    if (status_path_.empty() || (frame && !frame->IsMain())) return;
    if (FILE* f = std::fopen((status_path_ + ".tmp").c_str(), "w")) {
        std::string u = url.ToString();
        std::fwrite(u.data(), 1, u.size(), f);
        std::fclose(f);
        std::rename((status_path_ + ".tmp").c_str(), status_path_.c_str());
    }
}


void WvClient::resize(int width, int height) {
    width_.store(width);
    height_.store(height);
    if (browser_) browser_->GetHost()->WasResized();
}
