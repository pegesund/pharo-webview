// Input control channel: tails a newline-delimited JSON file (the same format
// Pharo writes for the CDP backend) and dispatches CEF input events. Each line:
//   {"type":"click","x":..,"y":..}
//   {"type":"move","x":..,"y":..}
//   {"type":"scroll","x":..,"y":..,"dx":..,"dy":..}
//   {"type":"key","text":".."}
#ifndef WV_CONTROL_H
#define WV_CONTROL_H

#include <string>
#include "wv_client.h"

namespace WvControl {
// Starts a detached background thread tailing `path`, routing events to the
// browser owned by `client`. Safe to call once after the client exists.
void start(const std::string& path, CefRefPtr<WvClient> client);
}

#endif /* WV_CONTROL_H */
