#!/bin/bash
# Build (and ad-hoc codesign) cef_host.app.
#
# Prereqs: cmake, ninja, Xcode command-line tools, and the CEF distribution
# extracted to cef_host/third_party/cef (see scripts/fetch-cef.sh).
#
# For LOCAL use, ad-hoc signing (codesign -s -) is enough — the CMake build
# already does it. For DISTRIBUTION you need a Developer ID Application cert and
# notarization; see docs/DISTRIBUTION.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="$ROOT/cef_host"
BUILD="$HOST/build"

if [ ! -d "$HOST/third_party/cef/Release" ]; then
  echo "ERROR: CEF not found at $HOST/third_party/cef"
  echo "Run scripts/fetch-cef.sh first (or extract a CEF minimal distribution there)."
  exit 1
fi

mkdir -p "$BUILD"
cmake -G Ninja -DPROJECT_ARCH=arm64 -S "$HOST" -B "$BUILD" >/dev/null
ninja -C "$BUILD"

APP="$BUILD/cef_host.app"
echo "== verifying signature =="
codesign --verify --deep --strict "$APP" && echo "signature OK (ad-hoc)"
echo "== built: $APP"
echo "   run: \"$APP/Contents/MacOS/cef_host\" <url> <w> <h> <shm> <input>"
