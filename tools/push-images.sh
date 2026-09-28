#!/bin/bash
# Stage a build's bootloader-flashable images (see flash-bl.sh) on the USB host.
# The link to the Mac is slow (~4 MB/s over the VPN), so super.img is seeded
# with an APFS clone of the newest staged super.img and rsync sends only the
# changed blocks.
# Usage: push-images.sh <build-id>
set -euo pipefail
. "$(dirname "$0")/env"
id=${1:?build-id}
out=$DIZI_ROOT/evox/$DIZI_OUT_NAME/target/product/$DIZI_DEVICE
# An archived build (tools/archive-build.sh) takes precedence over the live out/.
[[ -d $DIZI_ROOT/builds/$id ]] && out=$DIZI_ROOT/builds/$id
imgs=(android-info.txt boot.img vendor_boot.img dtbo.img recovery.img vbmeta.img
	vbmeta_system.img super.img)
mkdir -p "$DIZI_ROOT/logs/$id"
(cd "$out" && sha256sum "${imgs[@]}") > "$DIZI_ROOT/logs/$id/images.sha256"
# The remote shell is macOS zsh: keep the command POSIX.
ssh -i "$DIZI_SSH_KEY" "$DIZI_HOST" "mkdir -p $DIZI_REMOTE_DIR/$id && cd $DIZI_REMOTE_DIR &&
	if [ ! -f $id/super.img ]; then
		prev=\$(ls -t */super.img 2>/dev/null | head -1)
		[ -n \"\$prev\" ] && cp -c \"\$prev\" $id/super.img && echo \"seeded super.img from \$prev\"
	fi; true"
rsync -e "ssh -C -i $DIZI_SSH_KEY" --stats -t --no-whole-file "${imgs[@]/#/$out/}" \
	"$DIZI_HOST:$DIZI_REMOTE_DIR/$id/" | grep -E 'Literal data|Matched data|Total transferred'
ssh -i "$DIZI_SSH_KEY" "$DIZI_HOST" "cd $DIZI_REMOTE_DIR/$id && shasum -a 256 ${imgs[*]}" |
	diff - "$DIZI_ROOT/logs/$id/images.sha256" && echo "staged $id on $DIZI_HOST"
