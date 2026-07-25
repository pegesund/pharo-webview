#!/bin/bash
# Download and extract the CEF minimal distribution for macOS arm64 into
# cef_host/third_party/cef. Pin the version here so builds are reproducible.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/cef_host/third_party"

# CEF 138 stable (chromium 138) — verified working with this project's OSR setup.
CEF_VER="150.0.14+g7c1aa68+chromium-150.0.7871.129"
FILE="cef_binary_${CEF_VER}_macosarm64_minimal.tar.bz2"
# URL-encode the '+' characters
ENC=$(printf '%s' "$FILE" | sed 's/+/%2B/g')
URL="https://cef-builds.spotifycdn.com/${ENC}"

mkdir -p "$DEST"
cd "$DEST"

if [ -d cef/Release ]; then
  echo "CEF already present at $DEST/cef — skipping download."
  exit 0
fi

echo "Downloading CEF $CEF_VER ..."
curl -# -L -o cef.tar.bz2 "$URL"
echo "Extracting ..."
rm -rf cef && mkdir cef
tar xjf cef.tar.bz2 -C cef --strip-components=1
rm cef.tar.bz2
echo "CEF ready at $DEST/cef"
