#!/bin/sh
# Evolution X for the Redmi Pad Pro 5G / POCO Pad 5G (ruan): first install from fastboot.
#
# Run from the unpacked fastboot package, with the tablet in the bootloader
# (power + volume down) and connected over USB. The bootloader must be unlocked.
#
#   ./flash-ruan.sh           clean install: WIPES ALL DATA (needed the first time)
#   ./flash-ruan.sh --keep    update in place from a previous build of this ROM
#
# Only the partitions this ROM ships are written (boot, vendor_boot, dtbo, vbmeta,
# vbmeta_system, recovery, super, misc). Firmware (modem, xbl, tz, ...) is never
# touched. Never relock the bootloader with this ROM installed.
set -e

cd "$(dirname "$0")"
keep=
[ "${1:-}" = "--keep" ] && keep=1

fail() { echo "error: $*" >&2; exit 1; }
command -v fastboot >/dev/null 2>&1 || fail "fastboot not found (install Android platform-tools)"
for f in boot.img vendor_boot.img dtbo.img vbmeta.img vbmeta_system.img recovery.img super.img misc.img; do
	[ -f "$f" ] || fail "$f missing: run this from the unpacked package"
done
if command -v sha256sum >/dev/null 2>&1; then sha256sum -c SHA256SUMS >/dev/null || fail "checksum mismatch"
elif command -v shasum >/dev/null 2>&1; then shasum -a 256 -c SHA256SUMS >/dev/null || fail "checksum mismatch"
fi

product=$(fastboot getvar product 2>&1 | sed -n 's/^product: *//p')
[ "$product" = "ruan" ] || fail "connected device is '${product:-none}', not ruan"
fastboot getvar is-userspace 2>&1 | grep -q 'is-userspace: no' ||
	fail "reboot to the bootloader (not fastbootd/recovery) first"
fastboot getvar unlocked 2>&1 | grep -q 'unlocked: yes' || fail "the bootloader is locked"

if [ -z "$keep" ]; then
	printf 'This erases ALL data on the tablet. Type "yes" to continue: '
	read -r answer
	[ "$answer" = "yes" ] || fail "aborted"
fi

fastboot flash super super.img
for p in boot vendor_boot dtbo vbmeta vbmeta_system recovery; do
	fastboot flash "${p}_a" "$p.img"
	fastboot flash "${p}_b" "$p.img"
done
if [ -z "$keep" ]; then
	# Erase, don't format: /data uses metadata encryption and must be created
	# by the first boot (formatting from fastboot causes a boot loop).
	fastboot erase metadata
	fastboot erase userdata
fi
fastboot flash misc misc.img
fastboot set_active a
fastboot reboot
echo "Done. The first boot takes a few minutes."
