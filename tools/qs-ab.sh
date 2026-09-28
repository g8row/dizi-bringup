#!/bin/bash
# A/B a display/SF tweak on the quick settings pulldown.
# Usage: tools/qs-ab.sh <build-id> <label> '<adb shell command to apply>' ['<command to revert>']
# Runs QS-only ui-jank before and after; the composer is restarted after apply.
set -uo pipefail
T=$(dirname "$0")
id=$1; label=$2; apply=$3; revert=${4:-}
run() { QS_ONLY=1 "$T/ui-jank.sh" "$id" 16 landscape 2>&1 | grep -E '^systemui|clientCompositionFrames|missedFrames' | head -3; }
echo "== $label: before"; run
"$T/remote.sh" adb shell "$apply" >/dev/null 2>&1
sleep 8
echo "== $label: after"; run
[[ -n $revert ]] && { "$T/remote.sh" adb shell "$revert" >/dev/null 2>&1; sleep 8; }
