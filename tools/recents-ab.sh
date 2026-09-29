#!/bin/bash
# Recents -> app A/B line: warm-up plus N measured runs of recents-open-jank.sh with the same two
# apps on every ROM (Settings, Clock). Prints launcher hwui janky % and SF display-timeline janky %.
# Usage: tools/recents-ab.sh <build-id> <label> [runs]
set -uo pipefail
T=$(dirname "$0")
id=${1:?build-id}; label=${2:?label}; runs=${3:-2}
export RECENTS_TARGETS=${RECENTS_TARGETS:-Settings Clock}
one() {
	local r
	r=$("$T/recents-open-jank.sh" "$id" 10 2>/dev/null | grep "^results:" | awk '{print $2}')
	printf '%s/%s ' "$(grep -oE "Janky frames: [0-9]+ \([0-9.]+%\)" "$r/summary.txt" | grep -oE "[0-9.]+%" | head -1)" \
		"$(awk '$4 == "(display)" {print $3}' "$r/summary.txt" | head -1)"
}
"$T/recents-open-jank.sh" "$id" 10 >/dev/null 2>&1   # warm-up
line="$(printf '%-34s' "$label") launcher/display:"
for ((i = 0; i < runs; i++)); do line+=" $(one)"; done
echo "$line" | tee -a "$(dirname "$T")/logs/$id/recents-ab.txt"
