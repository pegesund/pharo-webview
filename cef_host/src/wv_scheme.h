// Registers the "lese://" custom scheme so the PDF viewer can be served with a
// real, secure origin (ES modules + fetch work) WITHOUT a local TCP web server
// -- avoiding firewall prompts and port conflicts. Files are read straight off
// disk: "/pdf/<id>" -> <assetroot>/<id>.pdf, everything else -> the pdf.js tree.
// Roots come from env (WV_LESE_WEBROOT / WV_LESE_ASSETROOT) with dev fallbacks.
#ifndef WV_SCHEME_H
#define WV_SCHEME_H

// Call once from CefBrowserProcessHandler::OnContextInitialized (UI thread).
void WvRegisterLeseScheme();

#endif  // WV_SCHEME_H
