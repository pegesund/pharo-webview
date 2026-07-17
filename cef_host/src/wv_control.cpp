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

// macOS native (virtual) key code for a printable ASCII char, so the DOM
// keydown reports the right event.code/key. 0 if unknown.
int macNativeForChar(char c) {
    if (c >= 'a' && c <= 'z') c -= 32;  // fold to uppercase
    switch (c) {
        case 'A': return 0;  case 'S': return 1;  case 'D': return 2;  case 'F': return 3;
        case 'H': return 4;  case 'G': return 5;  case 'Z': return 6;  case 'X': return 7;
        case 'C': return 8;  case 'V': return 9;  case 'B': return 11; case 'Q': return 12;
        case 'W': return 13; case 'E': return 14; case 'R': return 15; case 'Y': return 16;
        case 'T': return 17; case 'O': return 31; case 'U': return 32; case 'I': return 34;
        case 'P': return 35; case 'L': return 37; case 'J': return 38; case 'K': return 40;
        case 'N': return 45; case 'M': return 46;
        case '1': return 18; case '2': return 19; case '3': return 20; case '4': return 21;
        case '5': return 23; case '6': return 22; case '7': return 26; case '8': return 28;
        case '9': return 25; case '0': return 29; case ' ': return 49;
        default: return 0;
    }
}

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
        // Carry the left-button-held state so a drag becomes a text selection.
        if (intOf(d, "buttons") & 1) m.modifiers |= EVENTFLAG_LEFT_MOUSE_BUTTON;
        host->SendMouseMoveEvent(m, false);
    } else if (type == "down") {
        host->SendMouseClickEvent(m, MBT_LEFT, false, 1);  // press (no release)
    } else if (type == "up") {
        host->SendMouseClickEvent(m, MBT_LEFT, true, 1);   // release
    } else if (type == "click") {
        host->SendMouseClickEvent(m, MBT_LEFT, false, 1);  // down
        host->SendMouseClickEvent(m, MBT_LEFT, true, 1);   // up
    } else if (type == "scroll") {
        host->SendMouseWheelEvent(m, intOf(d, "dx"), intOf(d, "dy"));
    } else if (type == "navigate") {
        std::string url = d->HasKey("url") ? d->GetString("url").ToString() : "";
        if (!url.empty()) browser->GetMainFrame()->LoadURL(url);
    } else if (type == "eval") {
        // Run arbitrary JS in the main frame (DOM manipulation, and — when the
        // JS calls window.pharo.emit — request/response back to Pharo).
        std::string js = d->HasKey("js") ? d->GetString("js").ToString() : "";
        if (!js.empty()) {
            CefRefPtr<CefFrame> mf = browser->GetMainFrame();
            mf->ExecuteJavaScript(js, mf->GetURL(), 0);
        }
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

        // Native keydown: fires the DOM keydown AND the browser default action
        // (caret move / scrolling / delete / submit).
        //
        // NOTE: in --single-process mode SendKeyEvent(KEYEVENT_KEYUP) mis-fires as
        // a SECOND keydown (verified: keyup-only -> down:1 up:0), so we cannot emit
        // a native keyup. Instead we synthesize the DOM 'keyup' with JavaScript so
        // page keyup listeners fire — behaviour matches a real browser for JS.
        if (code != 0) {
            int native = 0;
            const char* keyName = "";
            switch (code) {
                case 37: native = 123; keyName = "ArrowLeft";  break;
                case 39: native = 124; keyName = "ArrowRight"; break;
                case 38: native = 126; keyName = "ArrowUp";    break;
                case 40: native = 125; keyName = "ArrowDown";  break;
                case 33: native = 116; keyName = "PageUp";     break;
                case 34: native = 121; keyName = "PageDown";   break;
                case 36: native = 115; keyName = "Home";       break;
                case 35: native = 119; keyName = "End";        break;
                case 8:  native = 51;  keyName = "Backspace";  break;
                case 9:  native = 48;  keyName = "Tab";        break;
                case 13: native = 36;  keyName = "Enter";      break;
                case 27: native = 53;  keyName = "Escape";     break;
                case 46: native = 117; keyName = "Delete";     break;
            }
            CefKeyEvent k;
            k.modifiers = 0;
            k.is_system_key = false;
            k.windows_key_code = code;
            k.native_key_code = native;
            k.type = KEYEVENT_RAWKEYDOWN;
            host->SendKeyEvent(k);
            if (keyName[0]) {
                std::string js =
                    "(function(){var t=document.activeElement||document.body;"
                    "t.dispatchEvent(new KeyboardEvent('keyup',{key:'";
                js += keyName;
                js += "',code:'";
                js += keyName;
                js += "',keyCode:" + std::to_string(code) +
                      ",which:" + std::to_string(code) +
                      ",bubbles:true,cancelable:true}));})();";
                browser->GetMainFrame()->ExecuteJavaScript(js, "", 0);
            }
        } else if (!text.empty()) {
            // Printable text: send RAWKEYDOWN then CHAR. The RAWKEYDOWN makes each
            // keystroke self-contained so it resets the input pipeline — otherwise
            // the character right after a special key (whose native KEYUP we can't
            // send in single-process) gets absorbed as that key's missing CHAR.
            // Decode the FIRST UTF-8 code point of `text` (the Pharo side sends the
            // character UTF-8 encoded). The previous code used (char16_t)text[0],
            // which sign-extended the leading byte of a multi-byte char (e.g. 'ø'
            // 0xC3 0xB8 -> 0xFFC3) and dropped the rest, so non-ASCII input (æøå and
            // every accented letter) never reached the page. Decode properly instead.
            unsigned char b0 = (unsigned char)text[0];
            unsigned int cp; size_t nb;
            if (b0 < 0x80) { cp = b0; nb = 1; }
            else if ((b0 & 0xE0) == 0xC0 && text.size() >= 2) {
                cp = ((b0 & 0x1F) << 6) | ((unsigned char)text[1] & 0x3F); nb = 2;
            } else if ((b0 & 0xF0) == 0xE0 && text.size() >= 3) {
                cp = ((b0 & 0x0F) << 12) | (((unsigned char)text[1] & 0x3F) << 6)
                     | ((unsigned char)text[2] & 0x3F); nb = 3;
            } else if ((b0 & 0xF8) == 0xF0 && text.size() >= 4) {
                cp = ((b0 & 0x07) << 18) | (((unsigned char)text[1] & 0x3F) << 12)
                     | (((unsigned char)text[2] & 0x3F) << 6)
                     | ((unsigned char)text[3] & 0x3F); nb = 4;
            } else { cp = b0; nb = 1; }
            (void)nb;
            // vkey uses an uppercase ASCII code where one exists; 0 for non-ASCII.
            int vk = 0;
            if (cp >= 'a' && cp <= 'z') vk = (int)cp - 32;
            else if (cp < 0x80) vk = (int)cp;
            // char16_t holds the BMP directly; anything above is rare for typed input.
            char16_t ch16 = (cp <= 0xFFFF) ? (char16_t)cp : (char16_t)0xFFFD;
            CefKeyEvent kd;
            kd.modifiers = 0;
            kd.is_system_key = false;
            kd.windows_key_code = vk;
            kd.native_key_code = (cp < 0x80) ? macNativeForChar((char)cp) : 0;
            kd.type = KEYEVENT_RAWKEYDOWN;
            host->SendKeyEvent(kd);
            CefKeyEvent kc2;
            kc2.modifiers = 0;
            kc2.is_system_key = false;
            kc2.type = KEYEVENT_CHAR;
            kc2.character = ch16;
            kc2.unmodified_character = ch16;
            kc2.windows_key_code = vk;
            host->SendKeyEvent(kc2);
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
