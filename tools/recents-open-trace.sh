#!/bin/bash
# Perfetto trace of Recents -> app cycles: SF frame timeline, gfx/view/wm atrace, GPU and CPU
# frequency, and RPHASE logcat markers (overview/open/home/idle) to split the jank by phase.
# Works on user builds. Usage: tools/recents-open-trace.sh <build-id> [cycles]
# Analyse with trace_processor_shell (evox/prebuilts/tools/linux-x86_64/perfetto/).
set -euo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
id=${1:?build-id}; cycles=${2:-6}
out=$DIZI_ROOT/logs/$id/recents-open-trace-$(date +%H%M%S)
mkdir -p "$out"
a() { "$R" adb "$@" </dev/null 2>/dev/null | tr -d '\r'; }
dev=/data/misc/perfetto-traces/recents-open.pftrace

a shell "rm -f $dev"
ssh -i "$DIZI_SSH_KEY" "$DIZI_HOST" \
	"/opt/homebrew/bin/adb -s $DIZI_SERIAL shell perfetto --txt -c - -o $dev --background" \
	< "$DIZI_ROOT/tools/perfetto/recents-open.pbtxt" >/dev/null
sleep 2
a shell 'svc power stayon usb; input keyevent WAKEUP; wm dismiss-keyguard; input keyevent HOME'
sleep 2
for ((i = 0; i < cycles; i++)); do
	t=$( ((i % 2)) && echo Chrome || echo Settings )
	xy=$(a shell 'log -t RPHASE overview; input keyevent APP_SWITCH; sleep 1.5; uiautomator dump /sdcard/o.xml >/dev/null; cat /sdcard/o.xml' |
		grep -o '<node [^>]*>' | grep 'id/snapshot' | grep "content-desc=\"$t\"" | head -1 |
		sed -E 's/.*bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]".*/\1 \2 \3 \4/' |
		awk '{print int(($1 + $3) / 2), int(($2 + $4) / 2)}' || true)
	[[ -n $xy ]] || { echo "cycle $i: no $t card" >&2; continue; }
	a shell "log -t RPHASE open; input tap $xy; sleep 2; log -t RPHASE home; input keyevent HOME; sleep 1.5; log -t RPHASE idle"
done
sleep 1
a shell 'pkill -INT perfetto' || true  # already stopped if the cycles outlast duration_ms
sleep 4
ssh -i "$DIZI_SSH_KEY" "$DIZI_HOST" "/opt/homebrew/bin/adb -s $DIZI_SERIAL exec-out cat $dev" > "$out/trace.pftrace"
ls -l "$out/trace.pftrace"
echo "results: $out"
