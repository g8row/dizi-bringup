#!/bin/bash
# Flash a staged build with fastboot flashall (boot, vendor_boot, dtbo,
# recovery, vbmeta*, then super via fastbootd). Firmware is never touched.
# Usage: flash.sh <build-id> [--wipe] [--slot a|b]
set -euo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
id=${1:?build-id}; shift
wipe=; slot=b
while (($#)); do
	case $1 in
	--wipe) wipe=-w ;;
	--slot) slot=$2; shift ;;
	*) echo "unknown option $1" >&2; exit 1 ;;
	esac
	shift
done

if "$R" adb get-state 2>/dev/null | grep -qE 'device|recovery'; then
	"$R" adb reboot bootloader
fi
for _ in $(seq 60); do
	"$R" fastboot devices | grep -q . && break
	sleep 2
done
"$R" fastboot getvar product 2>&1 | grep -q 'product: dizi' || { echo "not dizi?" >&2; exit 1; }

ssh -i "$DIZI_SSH_KEY" "$DIZI_HOST" \
	"export PATH=/opt/homebrew/bin:\$PATH ANDROID_SERIAL=$DIZI_SERIAL ANDROID_PRODUCT_OUT=\$HOME/$DIZI_REMOTE_DIR/$id
	 fastboot --slot=$slot --set-active=$slot --skip-secondary $wipe flashall --skip-reboot" \
	2>&1 | tee "$DIZI_ROOT/logs/$id/flash.log"
"$R" fastboot reboot
echo "flashed $id to slot $slot; run capture.sh $id"
