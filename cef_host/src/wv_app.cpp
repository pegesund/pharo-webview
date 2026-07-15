#include "wv_app.h"
#include "wv_control.h"

#include "include/cef_browser.h"
#include "include/cef_frame.h"
#include "include/cef_parser.h"
#include "include/cef_v8.h"
#include "include/wrapper/cef_helpers.h"

// Kept in sync with wv_client.cpp's OnLoadStart fallback injection.
static const char* kPharoBridgeJS =
    "window.pharo=window.pharo||{emit:function(n,d){try{"
    "console.log('__PHARO__'+JSON.stringify({event:'js',name:n,"
    "data:(d===undefined?null:d)}));}catch(e){}}};";

WvApp::WvApp(WvShm* shm, std::string url, int width, int height,
             std::string control_path)
    : shm_(shm),
      url_(std::move(url)),
      width_(width),
      height_(height),
      control_path_(std::move(control_path)) {}

void WvApp::OnBeforeCommandLineProcessing(const CefString&,
                                          CefRefPtr<CefCommandLine> command_line) {
    // Offscreen rendering is more reliable with the GPU process disabled;
    // OnPaint then comes from the software compositor.
    // The viz display compositor lives in the GPU process; in this headless,
    // sandbox-less host that subprocess cannot function (it exited with 15),
    // so no frames were produced. Run the GPU/viz IN the browser process where
    // our message loop drives it, with the SwiftShader software GL backend.
    // Headless macOS has no display, so a separate GPU process cannot create a
    // GL/Metal context and Chromium fatally aborts with "GPU process isn't
    // usable. Goodbye." Run viz IN the browser process (no separate GPU process
    // to be declared unusable) with the SwiftShader software GL backend.
    command_line->AppendSwitch("in-process-gpu");
    command_line->AppendSwitch("disable-gpu-sandbox");
    command_line->AppendSwitch("single-process");
    // Do NOT touch the macOS Keychain: ad-hoc signing changes the binary hash
    // every build, so the Keychain ACL re-prompts endlessly and blocks startup
    // (which also stalled OnPaint). A mock keychain + basic password store
    // avoids the OS Keychain entirely.
    command_line->AppendSwitch("use-mock-keychain");
    command_line->AppendSwitchWithValue("password-store", "basic");
}

void WvApp::OnContextInitialized() {
    CEF_REQUIRE_UI_THREAD();

    client_ = new WvClient(shm_, width_, height_);
    if (!control_path_.empty()) {
        client_->setStatusPath(control_path_ + ".status");
        client_->setEventsPath(control_path_ + ".events");
    }

    CefWindowInfo window_info;
    window_info.SetAsWindowless(0);  // no parent -> offscreen rendering

    CefBrowserSettings browser_settings;
    browser_settings.windowless_frame_rate = 60;
    browser_settings.background_color = CefColorSetARGB(255, 255, 255, 255);

    fprintf(stderr, "[wv_host] OnContextInitialized: creating windowless browser %s\n",
            url_.c_str());
    fflush(stderr);
    bool ok = CefBrowserHost::CreateBrowser(window_info, client_, url_,
                                             browser_settings, nullptr, nullptr);
    fprintf(stderr, "[wv_host] CreateBrowser returned %d\n", ok);
    fflush(stderr);

    if (!control_path_.empty()) {
        WvControl::start(control_path_, client_);
    }
}

void WvApp::OnContextCreated(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame,
                             CefRefPtr<CefV8Context>) {
    // Runs in the render side before page scripts, so window.pharo.emit is
    // always defined (the OnLoadStart injection is a single-process fallback).
    if (frame) frame->ExecuteJavaScript(kPharoBridgeJS, frame->GetURL(), 0);
}
