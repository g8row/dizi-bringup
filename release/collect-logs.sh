#!/bin/bash
# Collect logs from a Redmi Pad Pro (dizi) / Redmi Pad Pro 5G, POCO Pad 5G (ruan) running this
# Evolution X build, into one archive to send to the maintainer.
#
# Usage: ./collect-logs.sh [output-dir]
# Needs adb (Android platform-tools) on PATH and USB debugging on (Settings > System >
# Developer options), or the tablet in recovery. Reproduce the problem first, then run this
# right away: the logs only reach back a few minutes.
#
# The logs can contain your phone number, IMEI, SIM and network details, and Wi-Fi names.
# Only send the archive to the maintainer.
set -uo pipefail

if ! command -v adb >/dev/null 2>&1; then
	echo "adb not found. Install Android platform-tools and put adb on PATH." >&2
	exit 1
fi

state=$(adb get-state 2>/dev/null | tr -d '\r')
if [[ $state != device && $state != recovery ]]; then
	echo "Waiting for the tablet (plug it in and allow USB debugging on its screen)..."
	adb wait-for-any-device
	state=$(adb get-state 2>/dev/null | tr -d '\r')
fi

adbsh() { adb shell "$@" 2>&1 | tr -d '\r'; }
device=$(adbsh getprop ro.product.device)
out=${1:-.}/logs-${device:-tablet}-$(date +%Y%m%d-%H%M%S)
mkdir -p "$out"
echo "Collecting from ${device:-tablet} ($state) into $out ..."

# Root (bench builds only) gives dmesg, pstore and tombstones directly; otherwise the bug
# report below has them.
adb root >/dev/null 2>&1 && adb wait-for-any-device >/dev/null 2>&1
sleep 2

if [[ $state == recovery ]]; then
	adbsh cat /tmp/recovery.log > "$out/recovery.log"
	adbsh dmesg > "$out/dmesg.txt"
else
	adbsh getprop > "$out/getprop.txt"
	adb logcat -b all -d 2>&1 | tr -d '\r' > "$out/logcat.txt"
	adb logcat -b radio -d 2>&1 | tr -d '\r' > "$out/logcat-radio.txt"
	adb logcat -b crash -d 2>&1 | tr -d '\r' > "$out/logcat-crash.txt"
	adbsh dmesg > "$out/dmesg.txt" || true
	adbsh 'getprop | grep init.svc' > "$out/services.txt"
	adbsh lshal -itp > "$out/lshal.txt"
	adbsh service list > "$out/service-list.txt"
	adbsh lsmod > "$out/lsmod.txt"
	adbsh getenforce > "$out/selinux.txt"
	for d in telephony.registry isub carrier_config phone connectivity wifi location battery; do
		adbsh dumpsys "$d" > "$out/dumpsys-$d.txt"
	done
	adbsh dumpsys activity service com.android.phone > "$out/dumpsys-phone-service.txt"
	adbsh 'ls -l /data/tombstones /data/anr' > "$out/tombstones-list.txt"
	adb pull /data/tombstones "$out/tombstones" >/dev/null 2>&1
	adb pull /data/anr "$out/anr" >/dev/null 2>&1
	# Works without root: dumpstate adds the kernel log, tombstones, ANRs and radio state.
	echo "Taking a bug report (1-3 minutes)..."
	adb bugreport "$out/bugreport.zip" >/dev/null 2>&1
fi
# Kernel log of the previous boot (after a crash or a reboot loop).
adb pull /sys/fs/pstore "$out/pstore" >/dev/null 2>&1

archive=$out.tar.gz
tar -czf "$archive" -C "$(dirname "$out")" "$(basename "$out")"
echo
echo "Done: $archive"
echo "Send this file, with a short description of what went wrong and when."
