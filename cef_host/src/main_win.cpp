// Browser-process entry point (Windows). Runs CEF windowless/OSR and streams
// frames into shared memory. Args:
//   cef_host.exe <url> <width> <height> <shm_path> <control_path> [cache_path]
//
// Built as a WIN32-subsystem exe so no console window pops up when Pharo
// launches it; stderr logging still works when a caller redirects it.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>

#include "include/cef_app.h"
#include "include/cef_command_line.h"

#include "wv_app.h"
#include "wv_shm.h"

#include <string>
#include <vector>
#include <cstdlib>
#include <cstdio>

// UTF-16 argv -> UTF-8 strings (shm/control paths may contain non-ASCII).
static std::vector<std::string> Utf8Args() {
    std::vector<std::string> out;
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return out;
    for (int i = 0; i < argc; ++i) {
        int len = WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, nullptr, 0, nullptr, nullptr);
        std::string s(len > 0 ? len - 1 : 0, '\0');
        if (len > 1)
            WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, &s[0], len, nullptr, nullptr);
        out.push_back(std::move(s));
    }
    LocalFree(argv);
    return out;
}

int APIENTRY wWinMain(HINSTANCE hInstance, HINSTANCE, LPWSTR, int) {
    CefMainArgs main_args(hInstance);

    // Safety net: if this binary was launched as a CEF sub-process (with
    // --single-process there normally are none, but utility processes can
    // still appear), run the sub-process logic and exit.
    int exit_code = CefExecuteProcess(main_args, nullptr, nullptr);
    if (exit_code >= 0) {
        return exit_code;
    }

    std::vector<std::string> args = Utf8Args();
    std::string url = args.size() > 1 ? args[1] : "https://example.com";
    int width = args.size() > 2 ? std::atoi(args[2].c_str()) : 800;
    int height = args.size() > 3 ? std::atoi(args[3].c_str()) : 600;
    std::string shm_path = args.size() > 4 ? args[4] : "";
    std::string control_path = args.size() > 5 ? args[5] : "";
    // Optional 6th arg: a persistent cache/cookie dir (stable per slot).
    std::string cache_arg = args.size() > 6 ? args[6] : std::string();

    // Optional --wv-scale=N anywhere in argv: OSR device scale so web content
    // renders N times larger on a high-DPI display (the physical OnPaint buffer
    // stays width x height, matching the shm window). A private flag, not
    // Chromium's --force-device-scale-factor, so Chromium doesn't also apply it.
    float device_scale = 1.0f;
    for (const std::string& a : args) {
        const std::string key = "--wv-scale=";
        if (a.rfind(key, 0) == 0) {
            float v = (float)std::atof(a.c_str() + key.size());
            if (v > 0.1f) device_scale = v;
        }
    }

    if (shm_path.empty()) {
        char tmp[MAX_PATH];
        GetTempPathA(MAX_PATH, tmp);
        shm_path = std::string(tmp) + "wv-cef.shm";
    }
    if (control_path.empty()) {
        char tmp[MAX_PATH];
        GetTempPathA(MAX_PATH, tmp);
        control_path = std::string(tmp) + "wv-cef.input";
    }

    // Allocate the shared buffer at a generous maximum so the browser can be
    // resized up to it without remapping. The browser starts at width/height.
    const uint32_t kMaxW = 2560, kMaxH = 1600;
    WvShm shm;
    if (!shm.open(shm_path, kMaxW, kMaxH)) {
        fprintf(stderr, "[wv_host] failed to open shm at %s\n", shm_path.c_str());
        return 1;
    }

    CefRefPtr<WvApp> app(new WvApp(&shm, url, width, height, control_path, device_scale));

    CefSettings settings;
    settings.log_severity = LOGSEVERITY_WARNING;
    settings.windowless_rendering_enabled = true;
    settings.no_sandbox = true;
    settings.external_message_pump = false;
    settings.multi_threaded_message_loop = false;
    settings.persist_session_cookies = true;

    // A caller-supplied persistent cache dir (stable per browser "slot") lets
    // cookies persist across restarts. Falls back to a unique per-instance dir
    // when none is given, avoiding singleton-lock clashes between simultaneous
    // browsers (each live browser gets a distinct path either way).
    std::string cache = cache_arg.empty() ? (shm_path + ".cache") : cache_arg;
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
    return 0;
}
