#!/bin/bash
# Watch the tablet after a flash, classify the boot outcome and collect logs.
# Usage: capture.sh <build-id> [timeout-seconds]
set -uo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
id=${1:?build-id}; timeout=${2:-300}
n=1; while [[ -e $DIZI_ROOT/logs/$id/boot-$n ]]; do ((n++)); done
out=$DIZI_ROOT/logs/$id/boot-$n
mkdir -p "$out"
log() { echo "[$(date +%T)] $*" | tee -a "$out/summary.txt"; }

a() { "$R" adb "$@" </dev/null 2>/dev/null | tr -d '\r'; }

state=none; start=$SECONDS; last_cam=-30
while ((SECONDS - start < timeout)); do
	# Webcam frame every 30 s: shows logo / boot animation / black screen.
	if ((SECONDS - last_cam >= 30)); then
		last_cam=$SECONDS
		"$(dirname "$0")/cam.sh" "tmp-$id" >/dev/null 2>&1 &&
			mv "$DIZI_ROOT/logs/cam/tmp-$id.jpg" "$out/cam-$(printf %03d $((SECONDS - start))).jpg"
	fi
	st=$(a get-state)
	if [[ $st == device ]]; then
		state=adb
		[[ $(a shell getprop sys.boot_completed) == 1 ]] && { state=booted; break; }
	elif [[ $st == recovery ]]; then
		state=recovery; break
	elif "$R" fastboot devices </dev/null 2>/dev/null | grep -q .; then
		state=fastboot
	fi
	sleep 5
done
log "outcome after $((SECONDS - start))s: $state"

collect_android() {
	a root >/dev/null; sleep 3
	a shell getprop > "$out/getprop.txt"
	a logcat -b all -d > "$out/logcat.txt"
	a shell dmesg > "$out/dmesg.txt"
	a shell 'getprop | grep init.svc' > "$out/init-svc.txt"
	a shell 'ls -l /data/tombstones /data/anr' > "$out/tombstones-list.txt"
	a pull /data/tombstones "$out/tombstones" >/dev/null
	a shell 'lshal -itp' > "$out/lshal.txt"
	a shell 'service list' > "$out/service-list.txt"
	a shell 'cat /proc/bus/input/devices' > "$out/input-devices.txt"
	a shell 'lsmod' > "$out/lsmod.txt"
	grep -c 'avc:  denied' "$out/logcat.txt" | xargs -I{} echo "avc denials: {}" >> "$out/summary.txt"
	grep -E 'restarting|crashed|FATAL EXCEPTION|Abort message' "$out/logcat.txt" |
		sort | uniq -c | sort -rn | head -20 > "$out/crashes.txt"
	grep -iE 'init: .*(failed|error)|Unable to load|module .* failed' "$out/dmesg.txt" |
		head -40 > "$out/dmesg-errors.txt"
	log "bootanim=$(a shell getprop init.svc.bootanim) zygote=$(a shell getprop init.svc.zygote) selinux=$(a shell getenforce)"
}

collect_pstore() {
	a shell 'ls -la /sys/fs/pstore' > "$out/pstore-list.txt"
	a pull /sys/fs/pstore "$out/pstore" >/dev/null
	a shell 'cat /proc/last_kmsg 2>/dev/null' > "$out/last_kmsg.txt"
	log "pstore files: $(ls "$out/pstore" 2>/dev/null | tr '\n' ' ')"
}

case $state in
booted|adb) collect_android ;;
recovery)
	log "tablet fell into recovery (init fatal reboot target?) - pulling pstore"
	collect_pstore
	a shell 'cat /tmp/recovery.log' > "$out/recovery.log" ;;
fastboot)
	"$R" fastboot getvar all > "$out/getvar.txt" 2>&1
	log "bootloader rejected or bounced the image; see getvar.txt" ;;
none)
	log "no adb/fastboot: likely stuck in kernel or first stage."
	log "Force a warm reboot to recovery (hold Power + Vol Up), then run: capture.sh $id" ;;
esac
echo "logs: $out"
