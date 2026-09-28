#!/bin/bash
# Boot a source-built kernel once, without flashing anything: repack the
# build's boot.img with a new Image (same header and cmdline) and
# `fastboot boot` it. vendor_boot, dtbo and all modules stay as flashed.
# A normal reboot returns to the flashed kernel.
# Usage: tools/boot-kernel-test.sh <build-id> <Image>
set -euo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
id=${1:?build-id}; image=${2:?Image}
bin=$DIZI_ROOT/evox/out/host/linux-x86/bin
src=$DIZI_ROOT/evox/out/target/product/dizi/boot.img
work=$DIZI_ROOT/logs/$id/kernel-test
rm -rf "$work"; mkdir -p "$work"

"$bin/unpack_bootimg" --boot_img "$src" --out "$work/unpacked" --format mkbootimg > "$work/mkbootimg.args"
# The printed args point at the unpacked kernel; swap in the new one.
eval "args=($(cat "$work/mkbootimg.args"))"
for i in "${!args[@]}"; do
	[[ ${args[i]} == --kernel ]] && args[i + 1]=$image
done
"$bin/mkbootimg" "${args[@]}" --output "$work/boot-test.img"
ls -la "$work/boot-test.img"

ssh -i "$DIZI_SSH_KEY" "$DIZI_HOST" "mkdir -p $DIZI_REMOTE_DIR/$id"
rsync -q -e "ssh -C -i $DIZI_SSH_KEY" "$work/boot-test.img" "$DIZI_HOST:$DIZI_REMOTE_DIR/$id/boot-test.img"
if "$R" adb get-state 2>/dev/null | grep -q device; then "$R" adb reboot bootloader; fi
for _ in $(seq 60); do "$R" fastboot devices | grep -q . && break; sleep 2; done
"$R" fastboot getvar is-userspace 2>&1 | grep -q 'is-userspace: no' || { echo "not in the bootloader" >&2; exit 1; }
ssh -i "$DIZI_SSH_KEY" "$DIZI_HOST" "export PATH=/opt/homebrew/bin:\$PATH ANDROID_SERIAL=$DIZI_SERIAL
	fastboot boot \$HOME/$DIZI_REMOTE_DIR/$id/boot-test.img"
start=$SECONDS
until [[ $("$R" adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]]; do
	((SECONDS - start < 300)) || { echo "no boot_completed after 300 s: check tools/cam.sh, then reboot" >&2; exit 1; }
	sleep 5
done
echo "booted after $((SECONDS - start)) s"
"$R" adb shell 'uname -a; lsmod | tail -n +2 | wc -l' </dev/null
