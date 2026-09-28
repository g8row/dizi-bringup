#!/bin/bash
# Read-only capture of stock HyperOS state into recon/.
set -uo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
out=$DIZI_ROOT/recon
mkdir -p "$out/dumpsys"

sh_() { "$R" adb shell "$1" </dev/null | tr -d '\r'; }
su_() { "$R" adb shell "su -c '$1'" </dev/null | tr -d '\r'; }

"$R" adb wait-for-device </dev/null
sh_ getprop > "$out/getprop.txt"
su_ 'cat /proc/cmdline' > "$out/cmdline.txt"
su_ 'cat /proc/modules' > "$out/modules.txt"
su_ 'dmesg' > "$out/dmesg-boot.txt"
su_ 'lpdump' > "$out/lpdump.txt"
su_ 'ls -l /dev/block/by-name/' > "$out/by-name.txt"
su_ 'cat /proc/mounts' > "$out/mounts.txt"
su_ 'ls /sys/fs/pstore; cat /proc/iomem | grep -i -E "ramoops|pstore"' > "$out/pstore.txt"
su_ 'ls -laR /dev' > "$out/dev.txt" 2>/dev/null
su_ 'ls -la /sys/class/touch/touch_dev /sys/class/touch/tp_dev' > "$out/touch-sysfs.txt"
su_ 'cat /proc/bus/input/devices' > "$out/input-devices.txt"
sh_ 'getevent -il' > "$out/getevent-il.txt" &
sleep 3; kill $! 2>/dev/null
sh_ 'service list' > "$out/service-list.txt"
sh_ 'lshal -itp 2>/dev/null' > "$out/lshal.txt"
sh_ 'pm list packages -f' > "$out/packages.txt"
sh_ 'wm size; wm density' > "$out/wm.txt"
for s in display input sensorservice battery audio media.camera wifi bluetooth_manager \
	SurfaceFlinger power vibrator_manager; do
	sh_ "dumpsys $s" > "$out/dumpsys/$s.txt"
done

# Devicetree as seen by the running kernel (reference for a source kernel).
su_ 'cd /sys/firmware && tar cf - devicetree 2>/dev/null | base64' |
	base64 -d > "$out/devicetree.tar"
if [[ -s $out/devicetree.tar ]]; then
	rm -rf "$out/devicetree"; tar xf "$out/devicetree.tar" -C "$out"
	dtc -I fs -O dts -o "$out/running.dts" "$out/devicetree/base" 2>/dev/null
fi
echo "recon written to $out"
