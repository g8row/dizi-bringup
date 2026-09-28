#!/bin/bash
# Record kernel, input and logcat traffic while the user pairs/uses the pen
# on stock HyperOS. Usage: pen-capture.sh <label> [seconds]
set -uo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
label=${1:?label}; secs=${2:-90}
out=$DIZI_ROOT/recon/pen/$label
mkdir -p "$out"

"$R" adb wait-for-device </dev/null
"$R" adb shell "su -c 'dmesg -C'" </dev/null
"$R" adb logcat -c </dev/null
"$R" adb shell "su -c 'cat /proc/bus/input/devices'" </dev/null > "$out/input-before.txt"
"$R" adb shell "timeout $secs getevent -lt" </dev/null > "$out/getevent.txt" &
"$R" adb shell "su -c 'timeout $secs dmesg -w'" </dev/null > "$out/dmesg.txt" &
"$R" adb shell "timeout $secs logcat -b all -v threadtime" </dev/null > "$out/logcat.txt" &
echo "capturing '$label' for ${secs}s ..."
wait
"$R" adb shell "su -c 'cat /proc/bus/input/devices'" </dev/null > "$out/input-after.txt"
"$R" adb shell 'dumpsys input' </dev/null > "$out/dumpsys-input.txt"
"$R" adb shell 'dumpsys bluetooth_manager' </dev/null > "$out/dumpsys-bt.txt"
"$R" adb shell "su -c 'cat /sys/class/touch/touch_dev/pen_connect_strategy /sys/class/touch/touch_dev/palm_sensor 2>&1'" \
	</dev/null > "$out/touch-sysfs.txt"
grep -hE 'xiaomi_touch|pen_bluetooth|MIPP|mipp|pen' "$out/dmesg.txt" | head -50
