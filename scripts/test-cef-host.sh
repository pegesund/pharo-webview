#!/bin/bash
# Test cef_host WITHOUT Pharo: launch it on a URL, confirm it renders (writes frames
# into the shared-memory buffer) and runs as a Dock-less agent, then dump the frame
# to a PNG you can open.
#
#   scripts/test-cef-host.sh [url] [width] [height]
#
set -u
URL="${1:-https://www.wikipedia.org}"
W="${2:-900}"
H="${3:-650}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$DIR/cef_host/build/cef_host.app/Contents/MacOS/cef_host"
[ -x "$BIN" ] || { echo "cef_host not built. Run: bash scripts/build-cef-host.sh"; exit 1; }

TMP="$(mktemp -d)"
SHM="$TMP/wv.shm"; INPUT="$TMP/wv.input"; CACHE="$TMP/cache"; LOG="$TMP/host.log"
cleanup() { [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

echo "launching cef_host on $URL (${W}x${H}) ..."
"$BIN" "$URL" "$W" "$H" "$SHM" "$INPUT" "$CACHE" >"$LOG" 2>&1 &
PID=$!
# give it time to init + render a few frames
for i in $(seq 1 20); do
  sleep 0.5
  kill -0 "$PID" 2>/dev/null || { echo "cef_host exited early:"; tail -5 "$LOG"; exit 1; }
  grep -q 'initialised:' "$LOG" && break
done

echo "--- host log ---"; grep -E 'initialised|ERROR|FATAL' "$LOG" | head
echo "--- Dock icon check ---"
TYPE="$(lsappinfo info -only ApplicationType "$PID" 2>/dev/null | sed 's/.*=//')"
echo "ApplicationType=$TYPE   (\"UIElement\" = no Dock icon, correct)"

sleep 1  # let a couple more frames land
PNG="$DIR/cef_host/build/test-frame.png"
python3 - "$SHM" "$PNG" <<'PY'
import sys, struct
shm, out = sys.argv[1], sys.argv[2]
data = open(shm, 'rb').read()
magic, ver, w, h, seq, ndirty = struct.unpack_from('<IIIIII', data, 0)
if magic != 0x57565348:
    print("  shm magic mismatch -> not initialised"); sys.exit(1)
# header: 6 u32 + int32[64] + pixels_offset,pixels_capacity,alive,reserved
poff, pcap, alive = struct.unpack_from('<III', data, 24 + 64*4)
print(f"  magic=OK version={ver} frame={w}x{h} seq={seq} alive={alive} ({'RENDERED' if seq>0 else 'no frame yet'})")
px = data[poff:poff + w*h*4]
# BGRA -> PPM (RGB)
ppm = bytearray(b"P6\n%d %d\n255\n" % (w, h))
for i in range(0, w*h*4, 4):
    ppm += bytes((px[i+2], px[i+1], px[i]))
tmp_ppm = out + ".ppm"
open(tmp_ppm, 'wb').write(ppm)
import subprocess
subprocess.run(["sips", "-s", "format", "png", tmp_ppm, "--out", out],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
import os; os.remove(tmp_ppm)
print(f"  wrote {out}")
PY

echo "done. open the PNG to see the rendered page:  open '$PNG'"
