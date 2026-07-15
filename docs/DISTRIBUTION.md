# Distributing the CEF host (macOS)

`cef_host.app` embeds the Chromium Embedded Framework and launches helper
subprocesses. For **local use** the CMake build ad-hoc signs everything
(`codesign -s -`) and that is all you need — this is what the project uses today.

For **distribution to other machines** you must sign with a real identity and
notarize, or Gatekeeper will block it. Outline:

## 1. Requirements
- An Apple Developer account and a **Developer ID Application** certificate in
  your login keychain.
- `xcrun notarytool` credentials (an app-specific password or an API key).

## 2. Sign, inside-out
CEF bundles must be signed from the innermost code outward, each with the
hardened runtime. The framework and every `*.app` helper are signed first, then
the outer app. Sketch:

```bash
IDENT="Developer ID Application: Your Name (TEAMID)"
APP=cef_host.app
FW="$APP/Contents/Frameworks/Chromium Embedded Framework.framework"
ENT=cef_host/mac/entitlements.plist   # hardened-runtime entitlements

# framework (versioned bundle) and its libraries
codesign --force --timestamp --options runtime -s "$IDENT" \
  "$FW/Libraries/"* "$FW"

# each helper .app
for h in "$APP/Contents/Frameworks/"*" Helper.app"; do
  codesign --force --timestamp --options runtime --entitlements "$ENT" -s "$IDENT" "$h"
done

# the main executable then the app bundle
codesign --force --timestamp --options runtime --entitlements "$ENT" -s "$IDENT" \
  "$APP/Contents/MacOS/cef_host"
codesign --force --timestamp --options runtime --entitlements "$ENT" -s "$IDENT" "$APP"
```

Entitlements typically needed for an embedded Chromium (hardened runtime):
`com.apple.security.cs.allow-jit`,
`com.apple.security.cs.allow-unsigned-executable-memory`,
`com.apple.security.cs.disable-library-validation`.

## 3. Notarize
```bash
ditto -c -k --keepParent cef_host.app cef_host.zip
xcrun notarytool submit cef_host.zip --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple cef_host.app
```

## 4. Verify
```bash
codesign --verify --deep --strict --verbose=2 cef_host.app
spctl -a -vv cef_host.app     # should say: accepted, Notarized Developer ID
```

## Notes for this project
- The runtime path to `cef_host` is configured on the Pharo side via
  `WebViewCefMorph class>>binaryPath` (override it, or set the `WV_CEF_HOST`
  env var which it checks first). Point it at the distributed bundle.
- CEF runs with `--single-process --in-process-gpu` here (headless macOS has no
  usable separate GPU process); the sandbox is disabled (`no_sandbox`), so no
  sandbox entitlements are required, but the hardened-runtime ones above are.
