#!/bin/bash
# App start benchmark over adb (quiet: no audio, dim screen).
#  cold: force-stop, then `am start -W`; median TotalTime of N runs per app.
#  swap: open all apps once (memory pressure), then return to each, reporting
#        the launch state (HOT/WARM/COLD) and TotalTime. Returning apps whose pages
#        went to zram exercises the zram decompressor.
# Usage: tools/app-start.sh <build-id> [runs]
set -uo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
id=${1:?build-id}; runs=${2:-5}
out=$DIZI_ROOT/logs/$id/app-start-$(date +%H%M%S)
mkdir -p "$out"
a() { "$R" adb "$@" </dev/null 2>/dev/null | tr -d '\r'; }

apps=(
	com.android.settings/.Settings
	com.google.android.deskclock/com.android.deskclock.DeskClock
	com.google.android.calculator/com.android.calculator2.Calculator
	com.google.android.apps.photos/.home.HomeActivity
	com.android.chrome/com.google.android.apps.chrome.Main
	com.google.android.apps.messaging/.ui.ConversationListActivity
	com.google.android.contacts/com.android.contacts.activities.PeopleActivity
	com.google.android.calendar/com.android.calendar.AllInOneActivity
	com.google.android.apps.maps/com.google.android.maps.MapsActivity
	com.android.vending/.AssetBrowserActivity
)
a shell 'svc power stayon usb; input keyevent WAKEUP; wm dismiss-keyguard; settings put system screen_brightness 10'
ok=()
for c in "${apps[@]}"; do
	a shell "cmd package resolve-activity --brief -c android.intent.category.LAUNCHER ${c%%/*}" | grep -q / && ok+=("$c")
done

median() { sort -n | awk '{v[NR]=$1} END {if (NR) print v[int((NR+1)/2)]; else print "-"}'; }
echo "== cold start, median of $runs (ms)" | tee "$out/summary.txt"
for c in "${ok[@]}"; do
	pkg=${c%%/*}
	for ((i = 0; i < runs; i++)); do
		a shell "am force-stop $pkg; sleep 0.5; am start -W -n $c" | awk '/TotalTime/ {print $2}'
		a shell 'input keyevent HOME'; sleep 1
	done > "$out/cold-$pkg.txt"
	printf '%-45s %s\n' "$pkg" "$(median < "$out/cold-$pkg.txt")" | tee -a "$out/summary.txt"
done

echo "== return after opening all apps (state, ms)" | tee -a "$out/summary.txt"
for c in "${ok[@]}"; do a shell "am start -W -n $c" >/dev/null; sleep 2; done
a shell 'input keyevent HOME'; sleep 2
for c in "${ok[@]}"; do
	r=$(a shell "am start -W -n $c" | awk '/LaunchState|TotalTime/ {printf "%s ", $2}')
	printf '%-45s %s\n' "${c%%/*}" "$r" | tee -a "$out/summary.txt"
	a shell 'input keyevent HOME'; sleep 1
done
a shell 'cat /sys/block/zram0/comp_algorithm; cat /sys/block/zram0/mm_stat' | tee -a "$out/summary.txt"
echo "results: $out"
