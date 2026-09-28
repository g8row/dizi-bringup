#!/bin/bash
# Keep a build's flashable images (the set push-images.sh stages) under builds/<id>, so
# later builds in the same out/ don't overwrite a build that hasn't been flashed yet.
# push-images.sh prefers builds/<id> when it exists.
# Usage: tools/archive-build.sh <build-id> [out-dir]
set -euo pipefail
. "$(dirname "$0")/env"
id=${1:?build-id}; out=${2:-$DIZI_ROOT/evox/out/target/product/dizi}
dst=$DIZI_ROOT/builds/$id
mkdir -p "$dst"
for f in android-info.txt boot.img vendor_boot.img dtbo.img recovery.img vbmeta.img vbmeta_system.img super.img; do
	cp --reflink=auto "$out/$f" "$dst/$f"
done
(cd "$dst" && sha256sum ./*) > "$dst/SHA256SUMS"
echo "archived $id in $dst ($(du -sh "$dst" | cut -f1))"
