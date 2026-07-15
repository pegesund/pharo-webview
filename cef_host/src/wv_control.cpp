#include "wv_control.h"

#include "include/cef_task.h"
#include "include/cef_parser.h"
#include "include/cef_browser.h"
#include "include/base/cef_bind.h"
#include "include/base/cef_callback.h"
#include "include/wrapper/cef_closure_task.h"

#include <thread>
#include <chrono>
#include <fstream>
#include <string>
#include <sys/stat.h>

namespace {

int intOf(CefRefPtr<CefDictionaryValue> d, const char* key, int dflt = 0) {
    if (!d->HasKey(key)) return dflt;
    auto v = d->GetValue(key);
    if (v && v->GetType() == VTYPE_INT) return v->GetInt();
    if (v && v->GetType() == VTYPE_DOUBLE) return (int)v->GetDouble();
    return dflt;
}

// Runs on the CEF UI thread.
void dispatchLine(CefRefPtr<WvClient> client, std::string line) {
    if (!client || !client->browser()) return;
    CefRefPtr<CefValue> val = CefParseJSON(line, JSON_PARSER_RFC);
    if (!val || val->GetType() != VTYPE_DICTIONARY) return;
    CefRefPtr<CefDictionaryValue> d = val->GetDictionary();
    std::string type = d->HasKey("type") ? d->GetString("type").ToString() : "";

    CefRefPtr<CefBrowserHost> host = client->browser()->GetHost();
    CefMouseEvent m;
    m.x = intOf(d, "x");
    m.y = intOf(d, "y");
    m.modifiers = 0;

    CefRefPtr<CefBrowser> browser = client->browser();

    if (type == "move") {
        host->SendMouseMoveEvent(m, false);
    } else if (type == "click") {
        host->SendMouseClickEvent(m, MBT_LEFT, false, 1);  // down
        host->SendMouseClickEvent(m, MBT_LEFT, true, 1);   // up
    } else if (type == "scroll") {
        host->SendMouseWheelEvent(m, intOf(d, "dx"), intOf(d, "dy"));
    } else if (type == "navigate") {
        std::string url = d->HasKey("url") ? d->GetString("url").ToString() : "";
        if (!url.empty()) browser->GetMainFrame()->LoadURL(url);
    } else if (type == "back") {
        if (browser->CanGoBack()) browser->GoBack();
    } else if (type == "forward") {
        if (browser->CanGoForward()) browser->GoForward();
    } else if (type == "reload") {
        browser->Reload();
    } else if (type == "stop") {
        browser->StopLoad();
    } else if (type == "resize") {
        int w = intOf(d, "w"), h = intOf(d, "h");
        if (w > 0 && h > 0) client->resize(w, h);
    } else if (type == "focus") {
        host->SetFocus(intOf(d, "on", 1) != 0);
    } else if (type == "key") {
        int code = intOf(d, "code", 0);  // windows virtual key code for special keys
        std::string text = d->HasKey("text") ? d->GetString("text").ToString() : "";
        CefKeyEvent k;
        k.modifiers = 0;
        if (code != 0) {
            // Special key (backspace, enter, arrows, ...): raw down + up.
            k.windows_key_code = code;
            k.type = KEYEVENT_RAWKEYDOWN;
            host->SendKeyEvent(k);
            if (!text.empty()) {
                k.type = KEYEVENT_CHAR;
                k.character = (char16_t)text[0];
                k.unmodified_character = (char16_t)text[0];
                host->SendKeyEvent(k);
            }
            k.type = KEYEVENT_KEYUP;
            host->SendKeyEvent(k);
        } else if (!text.empty()) {
            k.type = KEYEVENT_CHAR;
            k.character = (char16_t)text[0];
            k.unmodified_character = (char16_t)text[0];
            k.windows_key_code = (int)text[0];
            host->SendKeyEvent(k);
        }
    }
}

void tailLoop(std::string path, CefRefPtr<WvClient> client) {
    std::streamoff offset = 0;
    std::string partial;
    for (;;) {
        struct stat st;
        if (stat(path.c_str(), &st) == 0) {
            if ((std::streamoff)st.st_size < offset) {  // truncated
                offset = 0;
                partial.clear();
            }
            std::ifstream in(path, std::ios::binary);
            if (in) {
                in.seekg(offset);
                std::string chunk((std::istreambuf_iterator<char>(in)),
                                  std::istreambuf_iterator<char>());
                offset += (std::streamoff)chunk.size();
                partial += chunk;
                size_t nl;
                while ((nl = partial.find('\n')) != std::string::npos) {
                    std::string line = partial.substr(0, nl);
                    partial.erase(0, nl + 1);
                    if (!line.empty()) {
                        CefPostTask(TID_UI,
                                    base::BindOnce(&dispatchLine, client, line));
                    }
                }
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(15));
    }
}

}  // namespace

namespace WvControl {
void start(const std::string& path, CefRefPtr<WvClient> client) {
    std::thread(tailLoop, path, client).detach();
}
}
