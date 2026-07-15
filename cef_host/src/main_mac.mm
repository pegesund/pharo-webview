// Browser-process entry point (macOS). Runs CEF windowless/OSR and streams
// frames into shared memory. Args:
//   cef_host <url> <width> <height> <shm_path> <control_path>
#import <Cocoa/Cocoa.h>

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/wrapper/cef_library_loader.h"

#include "wv_app.h"
#include "wv_shm.h"

#include <string>
#include <cstdlib>

// NSApplication subclass required by CEF on macOS (CefAppProtocol).
@interface WvApplication : NSApplication <CefAppProtocol> {
@private
    BOOL handlingSendEvent_;
}
@end

@implementation WvApplication
- (BOOL)isHandlingSendEvent { return handlingSendEvent_; }
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
    handlingSendEvent_ = handlingSendEvent;
}
- (void)sendEvent:(NSEvent*)event {
    CefScopedSendingEvent sendingEventScoper;
    [super sendEvent:event];
}
@end

static std::string bundlePath() {
    return std::string([[[NSBundle mainBundle] bundlePath] UTF8String]);
}

int main(int argc, char* argv[]) {
    @autoreleasepool {
        // Load the CEF framework dynamically from the app bundle.
        CefScopedLibraryLoader library_loader;
        if (!library_loader.LoadInMain()) {
            fprintf(stderr, "[wv_host] failed to load CEF framework\n");
            return 1;
        }

        std::string url = argc > 1 ? argv[1] : "https://example.com";
        int width = argc > 2 ? std::atoi(argv[2]) : 800;
        int height = argc > 3 ? std::atoi(argv[3]) : 600;
        std::string shm_path = argc > 4 ? argv[4] : "/tmp/wv-cef.shm";
        std::string control_path = argc > 5 ? argv[5] : "/tmp/wv-cef.input";

        CefMainArgs main_args(argc, argv);
        [WvApplication sharedApplication];

        WvShm shm;
        if (!shm.open(shm_path, (uint32_t)width, (uint32_t)height)) {
            fprintf(stderr, "[wv_host] failed to open shm at %s\n", shm_path.c_str());
            return 1;
        }

        CefRefPtr<WvApp> app(new WvApp(&shm, url, width, height, control_path));

        CefSettings settings;
        settings.log_severity = LOGSEVERITY_VERBOSE;
        settings.windowless_rendering_enabled = true;
        settings.no_sandbox = true;
        settings.external_message_pump = false;
        settings.multi_threaded_message_loop = false;

        std::string base = bundlePath();
        std::string framework = base + "/Contents/Frameworks/Chromium Embedded Framework.framework";
        std::string helper = base + "/Contents/Frameworks/cef_host Helper.app/Contents/MacOS/cef_host Helper";
        CefString(&settings.framework_dir_path) = framework;
        CefString(&settings.browser_subprocess_path) = helper;
        CefString(&settings.main_bundle_path) = base;
        // Unique cache dir per instance -> no singleton-lock clash between
        // multiple simultaneous browsers/hosts.
        std::string cache = shm_path + ".cache";
        CefString(&settings.root_cache_path) = cache;

        if (!CefInitialize(main_args, settings, app.get(), nullptr)) {
            fprintf(stderr, "[wv_host] CefInitialize failed\n");
            return 1;
        }

        fprintf(stderr, "[wv_host] initialised: %s %dx%d shm=%s\n",
                url.c_str(), width, height, shm_path.c_str());
        fflush(stderr);

        CefRunMessageLoop();  // blocks until CefQuitMessageLoop

        CefShutdown();
        shm.setAlive(0);
    }
    return 0;
}
