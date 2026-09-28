#!/bin/bash
# Deep-sleep check with the USB cable unplugged: poll the tablet over adb-over-Wi-Fi
# every 2 min (suspend count, battery, current, top wakeup sources) until USB returns.
# Usage: tools/suspend-watch.sh <build-id> [wifi-serial]
set -uo pipefail
. "$(dirname "$0")/env"
id=${1:?build-id}; ws=${2:-192.168.0.147:5555}
out=$DIZI_ROOT/logs/$id/suspend-$(date +%H%M%S).txt
mkdir -p "$(dirname "$out")"
w() { ssh -i "$DIZI_SSH_KEY" "$DIZI_HOST" "export PATH=/opt/homebrew/bin:\$PATH; adb connect $ws >/dev/null 2>&1; adb -s $ws shell '$1'" 2>/dev/null; }
w 'svc power stayon false; settings put global stay_on_while_plugged_in 0; input keyevent SLEEP' >/dev/null
# Wait (up to 30 min) for the cable to be pulled, then watch until it returns.
for _ in $(seq 1 180); do
	w 'cat /sys/class/power_supply/usb/online' | grep -q 0 && break
	sleep 10
done
echo "unplugged at $(date +%H:%M:%S)" | tee -a "$out"
w 'input keyevent SLEEP' >/dev/null
for i in $(seq 1 20); do
	{
		echo "== $(date +%H:%M:%S)"
		w 'echo "suspend ok=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail) usb=$(cat /sys/class/power_supply/usb/online) level=$(cat /sys/class/power_supply/battery/capacity) current_uA=$(cat /sys/class/power_supply/battery/current_now)"
		  for s in /sys/class/wakeup/*; do echo "$(cat $s/prevent_suspend_time_ms 2>/dev/null) $(cat $s/name 2>/dev/null)"; done | sort -rn | head -4'
	} >> "$out"
	tail -6 "$out" | head -2
	grep -q 'usb=1' <(tail -6 "$out") && { echo "USB is back"; break; }
	sleep 120
done
echo "log: $out"
