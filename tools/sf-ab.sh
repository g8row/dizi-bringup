#!/bin/bash
# A/B SurfaceFlinger props live: set them, restart the framework (root: Magisk su or adb root),
# wait for the launcher, then run tools/recents-open-jank.sh (a warm-up run, then the measured one).
# debug.* props don't survive a reboot, so a reboot restores the build's values.
# Usage: tools/sf-ab.sh <build-id> <label> [prop=value ...]   (value "" clears a prop)
set -uo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
id=${1:?build-id}; label=${2:?label}; shift 2
a() { "$R" adb "$@" </dev/null 2>/dev/null | tr -d '\r'; }
su() { a shell "if [ -x /debug_ramdisk/su ]; then /debug_ramdisk/su -c '$1'; else su 0 sh -c '$1'; fi"; }

for kv in "$@"; do
	a shell "setprop ${kv%%=*} '${kv#*=}'"
done
su 'stop; start'
sleep 20
for i in $(seq 60); do
	a shell 'dumpsys activity activities | grep -m1 topResumedActivity' | grep -q nexuslauncher && break
	sleep 3
done
sleep 10
a shell 'input keyevent WAKEUP; wm dismiss-keyguard'
{
	echo "== $label: $*"
	for kv in "$@"; do k=${kv%%=*}; echo "$k -> $("$R" adb shell getprop "$k" </dev/null 2>/dev/null | tr -d '\r')"; done
} | tee -a "$DIZI_ROOT/logs/$id/sf-ab.txt"
"$(dirname "$0")/recents-open-jank.sh" "$id-$label" 10 landscape >/dev/null 2>&1
"$(dirname "$0")/recents-open-jank.sh" "$id-$label" 10 landscape 2>&1 | sed -n '1,4p' | tee -a "$DIZI_ROOT/logs/$id/sf-ab.txt"
d=$(ls -td "$DIZI_ROOT/logs/$id-$label"/recents-open-jank-* | head -1)
awk '/^Global aggregated jank payload/{g=1} /Rate|rate =|fps/{h=$0}
	g && /^jankyFrames =/{j=$3} g && /^sfLongGpuJankyFrames =/{printf "  [%s] janky=%s sfLongGpu=%s\n", h, j, $3; if (++n == 2) exit}' \
	"$d/sf-timestats.txt" | tee -a "$DIZI_ROOT/logs/$id/sf-ab.txt"
grep -E '^refreshRateSwitches' "$d/sf-timestats.txt" | tee -a "$DIZI_ROOT/logs/$id/sf-ab.txt"
