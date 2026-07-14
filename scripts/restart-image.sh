#!/bin/bash
# Restart the Pharo image used for the webview project if it is not running.
# The image runs PharoSmalltalkInteropServer (MCP bridge) — it was saved with
# the server running, so it comes back up after restart.
VM="/Users/pegesund/Documents/Pharo/vms/140-x64/Pharo.app/Contents/MacOS/Pharo"
IMAGE="/Users/pegesund/Documents/Pharo/images/Pharo14.0-SNAPSHOT.build.733.sha.3bbdb5b622.arch.64bit/Pharo14.0-browser.image"

if pgrep -f "Pharo14.0-browser|Pharo14.0-SNAPSHOT.build.733" > /dev/null; then
    echo "Image already running."
    exit 0
fi
echo "Image not running — starting..."
nohup "$VM" "$IMAGE" > /tmp/pharo-webview-image.log 2>&1 &
echo "Started pid $!"
