#include "wv_app.h"
#include "wv_control.h"

#include "include/cef_browser.h"
#include "include/cef_parser.h"
#include "include/wrapper/cef_helpers.h"

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
    command_line->AppendSwitchWithValue("enable-logging", "stderr");
    command_line->AppendSwitchWithValue("v", "1");
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

    CefWindowInfo window_info;
    window_info.SetAsWindowless(0);  // no parent -> offscreen rendering
    window_info.external_begin_frame_enabled = true;  // we drive frames

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

    // Start the input control channel once we have a client to route to.
    if (!control_path_.empty()) {
        WvControl::start(control_path_, client_);
    }
}
