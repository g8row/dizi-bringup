#!/bin/bash
# Wait for a build to finish, stage it on the Mac, flash it from the
# bootloader (keeping data unless --wipe), wait for boot and restore adb root.
# Usage: tools/deploy.sh <build-id> [--wipe]
set -euo pipefail
. "$(dirname "$0")/env"
T=$(dirname "$0")
id=${1:?build-id}; wipe=--no-wipe
[[ ${2:-} == --wipe ]] && wipe=
log=$DIZI_ROOT/logs/$id.log
stock_images=$DIZI_ROOT/stock/OS3.0.303.0.WNSEUXM/dizi_eea_global_images_OS3.0.303.0.WNSEUXM_16.0/images

until grep -q '^exit=' "$log"; do sleep 15; done
grep -q '^exit=0' "$log" || { echo "$id failed, not deploying" >&2; exit 1; }

"$T/push-images.sh" "$id" | tee /dev/stderr | grep -q "^staged $id" || { echo "staging failed" >&2; exit 1; }
rsync -q -t -e "ssh -i $DIZI_SSH_KEY" "$stock_images/misc.img" "$DIZI_HOST:$DIZI_REMOTE_DIR/$id/"
rsync -q -t -e "ssh -i $DIZI_SSH_KEY" "$DIZI_ROOT/recovery.img" "$DIZI_HOST:$DIZI_REMOTE_DIR/$id/rescue-recovery.img"

# shellcheck disable=SC2086
"$T/flash-bl.sh" "$id" $wipe | grep -E 'FAILED|error|flashed' || true

start=$SECONDS
until [[ $("$T/remote.sh" adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]]; do
	((SECONDS - start < 600)) || { echo "no boot_completed after 600 s" >&2; exit 1; }
	sleep 5
done
echo "booted after $((SECONDS - start)) s"
"$T/remote.sh" adb root >/dev/null 2>&1 || true
sleep 5
"$T/remote.sh" adb wait-for-device
echo "deployed $id"
