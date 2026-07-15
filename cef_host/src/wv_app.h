// CefApp for the browser process: creates the windowless browser once the CEF
// context is initialised, and owns the client + shared-memory writer.
#ifndef WV_APP_H
#define WV_APP_H

#include "include/cef_app.h"
#include "include/cef_browser_process_handler.h"
#include "include/cef_render_process_handler.h"
#include "wv_client.h"
#include "wv_shm.h"

#include <string>

class WvApp : public CefApp,
              public CefBrowserProcessHandler,
              public CefRenderProcessHandler {
public:
    WvApp(WvShm* shm, std::string url, int width, int height,
          std::string control_path);

    // CefApp
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
        return this;
    }
    CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override {
        return this;
    }
    void OnBeforeCommandLineProcessing(
        const CefString& process_type,
        CefRefPtr<CefCommandLine> command_line) override;

    // CefBrowserProcessHandler
    void OnContextInitialized() override;

    // CefRenderProcessHandler: inject the window.pharo bridge into every V8
    // context before any page script runs (single-process: same object).
    void OnContextCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                          CefRefPtr<CefV8Context> context) override;

    CefRefPtr<WvClient> client() { return client_; }

private:
    WvShm* shm_;
    std::string url_;
    int width_;
    int height_;
    std::string control_path_;
    CefRefPtr<WvClient> client_;

    IMPLEMENT_REFCOUNTING(WvApp);
};

#endif /* WV_APP_H */
