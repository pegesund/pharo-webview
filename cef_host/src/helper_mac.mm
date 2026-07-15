// Sub-process (helper) entry point on macOS. All CEF sub-processes (renderer,
// GPU, utility, ...) launch this executable; it just runs CefExecuteProcess.
#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"

#include <cstdio>

int main(int argc, char* argv[]) {
    fprintf(stderr, "[wv_helper] helper launched argc=%d\n", argc);
    fflush(stderr);
    CefScopedLibraryLoader library_loader;
    if (!library_loader.LoadInHelper()) {
        fprintf(stderr, "[wv_helper] LoadInHelper FAILED\n");
        fflush(stderr);
        return 1;
    }
    CefMainArgs main_args(argc, argv);
    return CefExecuteProcess(main_args, nullptr, nullptr);
}
