#include "wv_scheme.h"

#include "include/cef_scheme.h"
#include "include/cef_request.h"
#include "include/cef_stream.h"
#include "include/wrapper/cef_stream_resource_handler.h"

#include <algorithm>
#include <cstdlib>
#include <string>

namespace {

std::string EnvOr(const char* key, const std::string& fallback) {
    const char* v = std::getenv(key);
    return (v && *v) ? std::string(v) : fallback;
}

std::string WebRoot() {
    return EnvOr("WV_LESE_WEBROOT", "/Users/pegesund/dev/leserom/webassets/pdfjs");
}

std::string AssetRoot() {
    const char* home = std::getenv("HOME");
    return EnvOr("WV_LESE_ASSETROOT",
                 std::string(home ? home : "") + "/Documents/Leserom/assets");
}

// Extract the path component of a lese:// URL by hand (robust for a custom
// scheme regardless of CefParseURL's standard-scheme handling).
//   lese://app/web/viewer.html?file=/pdf/x  ->  /web/viewer.html
std::string PathOf(const std::string& url) {
    std::string::size_type scheme = url.find("://");
    if (scheme == std::string::npos) return "/";
    std::string::size_type pathStart = url.find('/', scheme + 3);
    if (pathStart == std::string::npos) return "/";
    std::string::size_type queryStart = url.find('?', pathStart);
    return url.substr(pathStart, queryStart == std::string::npos
                                     ? std::string::npos
                                     : queryStart - pathStart);
}

std::string MimeFor(const std::string& path) {
    std::string::size_type dot = path.rfind('.');
    std::string ext = (dot == std::string::npos) ? "" : path.substr(dot + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    if (ext == "html") return "text/html";
    if (ext == "mjs" || ext == "js") return "text/javascript";  // critical: modules
    if (ext == "css") return "text/css";
    if (ext == "pdf") return "application/pdf";
    if (ext == "png") return "image/png";
    if (ext == "svg") return "image/svg+xml";
    if (ext == "gif") return "image/gif";
    if (ext == "jpg" || ext == "jpeg") return "image/jpeg";
    if (ext == "json" || ext == "map") return "application/json";
    if (ext == "ttf") return "font/ttf";
    if (ext == "otf") return "font/otf";
    if (ext == "properties") return "text/plain";
    return "application/octet-stream";
}

// "/pdf/<id>" -> <assetroot>/<id>.pdf ; anything else -> pdf.js web tree.
std::string FileForPath(const std::string& path) {
    const std::string kPdf = "/pdf/";
    if (path.compare(0, kPdf.size(), kPdf) == 0) {
        return AssetRoot() + "/" + path.substr(kPdf.size()) + ".pdf";
    }
    return WebRoot() + path;
}

class LeseSchemeFactory : public CefSchemeHandlerFactory {
public:
    CefRefPtr<CefResourceHandler> Create(CefRefPtr<CefBrowser>,
                                         CefRefPtr<CefFrame>,
                                         const CefString&,
                                         CefRefPtr<CefRequest> request) override {
        std::string path = PathOf(request->GetURL().ToString());
        if (path.find("..") != std::string::npos) return nullptr;  // traversal guard
        std::string file = FileForPath(path);
        CefRefPtr<CefStreamReader> stream = CefStreamReader::CreateForFile(file);
        if (!stream) return nullptr;  // missing file -> default 404 handling
        return new CefStreamResourceHandler(MimeFor(file), stream);
    }

    IMPLEMENT_REFCOUNTING(LeseSchemeFactory);
};

}  // namespace

void WvRegisterLeseScheme() {
    CefRegisterSchemeHandlerFactory("lese", "app", new LeseSchemeFactory());
}
