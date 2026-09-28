#!/bin/bash
# Hardware validation over adb on a booted build. Writes
# logs/<build-id>/validate.txt (one "area: PASS|FAIL|INFO detail" per line).
# Usage: validate.sh <build-id>
set -uo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
id=${1:?build-id}
out=$DIZI_ROOT/logs/$id/validate.txt
mkdir -p "$(dirname "$out")"; : > "$out"
sh_() { "$R" adb shell "$1" </dev/null 2>/dev/null | tr -d '\r'; }
res() { printf '%-14s %-4s %s\n' "$1:" "$2" "$3" | tee -a "$out"; }
check() { # area, description, command, grep-pattern
	local v; v=$(sh_ "$3")
	if grep -qE "$4" <<<"$v"; then res "$1" PASS "$2"; else res "$1" FAIL "$2 ($(head -c 120 <<<"$v" | tr '\n' ' '))"; fi
}

"$R" adb root >/dev/null 2>&1; "$R" adb wait-for-device </dev/null

check boot       "sys.boot_completed" 'getprop sys.boot_completed' '^1$'
res   boot       INFO "boot time $(sh_ 'cut -d. -f1 /proc/uptime')s uptime, $(sh_ 'getprop ro.boottime.init' | head -c 20)"
res   selinux    INFO "$(sh_ getenforce)"
res   avc        INFO "$(sh_ 'dmesg | grep -c "avc:  denied"') denials in dmesg"
res   services   INFO "restarting: $(sh_ 'getprop | grep -E "init.svc.*\[restarting\]"' | tr '\n' ' ')"
res   tombstones INFO "$(sh_ 'ls /data/tombstones | wc -l') tombstones"

check display    "120Hz mode listed" 'dumpsys display | grep -oE "fps=[0-9.]+" | sort -u' 'fps=120'
check display    "panel 1600x2560"   'dumpsys display | grep -m1 -oE "[0-9]+ x [0-9]+"' '1600 x 2560|2560 x 1600'
check touch      "touchscreen input" 'dumpsys input | grep -E "^ +[0-9]+: "' 'NVTCapacitiveTouchScreen'
check touch      "pen input node"    'dumpsys input | grep -E "^ +[0-9]+: "' 'NVTCapacitivePen'
check hall       "hall sensor input" 'dumpsys input | grep -E "^ +[0-9]+: "' 'xiaomi-hall'
check brightness "backlight node"    'ls /sys/class/backlight/' '.'

check wifi       "wifi enabled"      'cmd wifi status' 'Wifi is enabled'
check bluetooth  "bt turns on"       'cmd bluetooth_manager enable >/dev/null; cmd bluetooth_manager wait-for-state:STATE_ON' 'Success'
check audio      "audio HAL running" 'ps -A -o NAME | grep -m1 android.hardware.audio.service' 'audio'
check audio      "speaker output"    'dumpsys media.audio_flinger | grep -m3 -E "Output device|out device"' 'SPEAKER|SPEAKER'
check sensors    "accelerometer"     'dumpsys sensorservice' 'Accelerometer'
check sensors    "light sensor"      'dumpsys sensorservice' 'Ambient Light'
check camera     "camera provider"   'dumpsys media.camera | grep -E "Number of camera devices"' '[1-9]'
check battery    "battery present"   'dumpsys battery' 'present: true'
res   battery    INFO "$(sh_ 'dumpsys battery | grep -E "level|status|AC powered|USB powered" | tr -s " " | tr "\n" " "')"
check storage    "FBE active"        'getprop ro.crypto.state' 'encrypted'
check usb        "usb HAL"           'service list | grep -c "android.hardware.usb.IUsb/"' '^[1-9]'
res   suspend    INFO "$(sh_ 'cat /sys/power/suspend_stats/success 2>/dev/null') successful suspends"

echo "results: $out"
