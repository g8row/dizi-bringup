#!/bin/bash
# One line of jank numbers for the launcher transition paths, for quick A/B runs: Recents -> app and
# icon -> app (10 cycles each, warm), launcher hwui janky % and SF display timeline janky %.
# Usage: tools/ab-quick.sh <build-id> <label>
set -uo pipefail
T=$(dirname "$0")
id=${1:?build-id}; label=${2:?label}
pct() { grep -oE "Janky frames: [0-9]+ \([0-9.]+%\)" "$1" | grep -oE "[0-9.]+%" | head -1; }
disp() { awk '$4 == "(display)" {print $3}' "$1" | head -1; }
r=$("$T/recents-open-jank.sh" "$id" 10 2>/dev/null | grep "^results:" | awk '{print $2}')
o=$("$T/app-open-jank.sh" "$id" 10 2>/dev/null | grep "^results:" | awk '{print $2}')
line=$(printf '%-28s recents: launcher %-7s display %-7s | icon-open: launcher %-7s display %-7s' "$label" \
	"$(pct "$r/summary.txt")" "$(disp "$r/summary.txt")" "$(pct "$o/summary.txt")" "$(disp "$o/summary.txt")")
echo "$line" | tee -a "$DIZI_ROOT/logs/$id/ab-quick.txt" 2>/dev/null || echo "$line"
