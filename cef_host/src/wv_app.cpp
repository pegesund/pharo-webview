#include "wv_app.h"
#include "wv_control.h"
#include "wv_scheme.h"

#include "include/cef_browser.h"
#include "include/cef_frame.h"
#include "include/cef_parser.h"
#include "include/cef_scheme.h"
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
    // KNOWN LIMITATION (OSR + single-process, reproduced on BOTH CEF 138 and CEF 150):
    // typing into a textarea enhanced by heavy per-keystroke JavaScript (e.g.
    // MediaWiki's wikiEditor / CodeMirror syntax highlighter) reliably aborts the
    // process with EXC_BREAKPOINT -- a renderer CHECK on the threaded compositor path
    // during a JS-driven re-render (the crashed stack shows v8 internals under the
    // paint/raster code). Findings from an exhaustive bisect:
    //   * --disable-javascript makes the same typing stable; plain inputs, textareas
    //     and search boxes never crash. So ordinary form input works -- only rich
    //     in-page editors trip it.
    //   * single-process is REQUIRED: OSR OnPaint produces no frames without it (the
    //     GPU/viz process cannot init on headless macOS -- "GPU process isn't usable.
    //     Goodbye", launch error 1003 -- even with --use-angle=swiftshader), so the
    //     crash cannot be isolated to a child process.
    //   * --disable-threaded-compositing stops the crash but also stops all frames
    //     (OnPaint rides that thread); --disable-threaded-animation keeps frames but
    //     still crashes. No font-backend toggle, raster-thread limit or frame-rate
    //     change avoids it. Bumping CEF 138 -> 150 did not help (identical crash).
    // Mitigation lives on the Pharo side: (1) every FFI read of the shm is bounds-
    // checked (WvSharedMemory>>safeFrameExtent) so a host that dies mid-write cannot
    // segfault the image; (2) a frozen shm + dead host is detected and the current
    // URL is relaunched, so the view self-heals instead of staying stale.
}

void WvApp::OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) {
    // "lese://" is a real, secure, same-origin scheme so the pdf.js viewer's ES
    // modules + fetch() work while being served straight off disk (no TCP server).
    registrar->AddCustomScheme(
        "lese",
        CEF_SCHEME_OPTION_STANDARD | CEF_SCHEME_OPTION_SECURE |
            CEF_SCHEME_OPTION_CORS_ENABLED | CEF_SCHEME_OPTION_FETCH_ENABLED);
}

void WvApp::OnContextInitialized() {
    CEF_REQUIRE_UI_THREAD();

    WvRegisterLeseScheme();

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
