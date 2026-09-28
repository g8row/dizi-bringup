#!/bin/bash
# Flash a staged build entirely from the bootloader, the way Xiaomi's
# flash_all.sh does: full super.img (system etc. land in the _a slots),
# boot images to both slots, wipe, clear misc, boot slot a. Never uses
# recovery-based fastbootd, never touches firmware.
# Needs super.img and misc.img (stock, zeros) staged next to the images;
# rescue-recovery.img (e.g. OrangeFox), if staged, replaces recovery_a.
# Usage: flash-bl.sh <build-id> [--no-wipe]
set -euo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
id=${1:?build-id}; shift
wipe=1
[[ ${1:-} == --no-wipe ]] && wipe=

if "$R" adb get-state 2>/dev/null | grep -qE 'device|recovery'; then
	"$R" adb reboot bootloader
fi
for _ in $(seq 60); do
	"$R" fastboot devices | grep -q . && break
	sleep 2
done
"$R" fastboot getvar product 2>&1 | grep -q 'product: dizi' || { echo "not dizi?" >&2; exit 1; }
"$R" fastboot getvar is-userspace 2>&1 | grep -q 'is-userspace: no' || { echo "not in the bootloader" >&2; exit 1; }

mkdir -p "$DIZI_ROOT/logs/$id"
# The remote shell is macOS zsh: keep the command POSIX.
ssh -i "$DIZI_SSH_KEY" "$DIZI_HOST" "set -e
	export PATH=/opt/homebrew/bin:\$PATH ANDROID_SERIAL=$DIZI_SERIAL
	cd \"\$HOME/$DIZI_REMOTE_DIR/$id\"
	fastboot flash super super.img
	for p in boot vendor_boot dtbo vbmeta vbmeta_system recovery; do
		fastboot flash \${p}_a \$p.img
		fastboot flash \${p}_b \$p.img
	done
	# A known-good rescue recovery (OrangeFox) on the slot we boot, if staged.
	if [ -f rescue-recovery.img ]; then
		fastboot flash recovery_a rescue-recovery.img
	fi
	if [ -n '$wipe' ]; then
		# Erase only: with metadata encryption Android must create the fs itself
		# inside dm-default-key. fastboot -w pre-formats ext4 here and the boot
		# then fails in vold mountFstab (build-13 boot-1).
		fastboot erase metadata
		fastboot erase userdata
	fi
	fastboot flash misc misc.img
	fastboot set_active a" 2>&1 | tee "$DIZI_ROOT/logs/$id/flash-bl.log"
"$R" fastboot reboot
echo "flashed $id (bootloader path, slot a); run capture.sh $id"
