// CefClient + CefRenderHandler: windowless (OSR) rendering into shared memory.
#ifndef WV_CLIENT_H
#define WV_CLIENT_H

#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_display_handler.h"
#include "wv_shm.h"

#include <atomic>

class WvClient : public CefClient,
                 public CefRenderHandler,
                 public CefLifeSpanHandler,
                 public CefLoadHandler,
                 public CefDisplayHandler {
public:
    WvClient(WvShm* shm, int width, int height);

    // CefClient
    CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }

    // CefDisplayHandler
    bool OnConsoleMessage(CefRefPtr<CefBrowser> browser, cef_log_severity_t level,
                          const CefString& message, const CefString& source,
                          int line) override;

    // CefLoadHandler
    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading,
                              bool canGoBack, bool canGoForward) override;

    // CefRenderHandler
    void GetViewRect(CefRefPtr<CefBrowser> browser, CefRect& rect) override;
    bool GetScreenInfo(CefRefPtr<CefBrowser> browser, CefScreenInfo& info) override;
    void OnPaint(CefRefPtr<CefBrowser> browser,
                 PaintElementType type,
                 const RectList& dirtyRects,
                 const void* buffer,
                 int width,
                 int height) override;
    void OnAcceleratedPaint(CefRefPtr<CefBrowser> browser,
                            PaintElementType type,
                            const RectList& dirtyRects,
                            const CefAcceleratedPaintInfo& info) override;

    // CefLifeSpanHandler
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;

    CefRefPtr<CefBrowser> browser() { return browser_; }
    void resize(int width, int height);

private:
    WvShm* shm_;
    std::atomic<int> width_;
    std::atomic<int> height_;
    CefRefPtr<CefBrowser> browser_;
    uint64_t frame_count_ = 0;

    IMPLEMENT_REFCOUNTING(WvClient);
};

#endif /* WV_CLIENT_H */
