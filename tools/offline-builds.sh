#!/bin/bash
# Build-only chain that survives the Claude session (no Mac needed):
# build-20 (pen KeyHandler), then merge staging and build-21 (desktop, Parts theme).
set -uo pipefail
D=/build/alex/dizi
cd "$D/evox/device/xiaomi/dizi" && git fetch -q "$D/trees/staging" HEAD && git merge -q --ff-only FETCH_HEAD
git log --oneline -1
"$D/tools/build.sh" build-21 evolution superimage -k
echo "offline builds done: $(grep -E '#### ' "$D/logs/build-21.log" | tail -1)"
