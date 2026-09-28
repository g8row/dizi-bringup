#!/bin/bash
# Fetch the latest webcam frame of the tablet from the Mac.
# The Mac runs ~/dizi/cam/camloop.command inside Terminal (camera permission is
# granted to Terminal, not sshd). Restart it with: ssh ... open -a Terminal ~/dizi/cam/camloop.command
# Usage: tools/cam.sh [name]   -> logs/cam/<name|timestamp>.jpg
. "$(dirname "$0")/env"
name=${1:-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$DIZI_ROOT/logs/cam"
scp -q -i "$DIZI_SSH_KEY" "$DIZI_HOST:dizi/cam/latest.jpg" "$DIZI_ROOT/logs/cam/$name.jpg" && echo "$DIZI_ROOT/logs/cam/$name.jpg"
