#!/bin/bash
# Sign a release build with our private keys and package it.
#   in:  the user target-files from `RELEASE=1 tools/build.sh <id> target-files-package otatools`
#   out: release/out/<name>/
#          <name>.zip           signed OTA (recovery sideload / updater)
#          <name>-fastboot.zip  images + flash-dizi.sh + INSTALL.md + SHA256SUMS
#          boot.img dtbo.img vendor_boot.img recovery.img  for the recovery + sideload install
# Keys: $DIZI_ROOT/keys (private, never commit). Missing APEX keys are generated.
# Usage: tools/sign-release.sh [name]
set -euo pipefail
. "$(dirname "$0")/env"
E=$DIZI_ROOT/evox
OUTR=$E/out-release
K=$DIZI_ROOT/keys
H=$OUTR/host/linux-x86
export PATH=$H/bin:$PATH
tf=$(ls -t "$OUTR"/target/product/dizi/obj/PACKAGING/target_files_intermediates/*-target_files*.zip | head -1)
date=$(date +%Y%m%d)
name=${1:-EvolutionX-16.0-$date-dizi-11.11-Unofficial}
work=$DIZI_ROOT/release/out/$name
mkdir -p "$work"
echo "target-files: $tf"

subject='/C=US/ST=Unknown/L=Unknown/O=dizi EvolutionX unofficial/OU=Release/CN=dizi EvolutionX'
# APEX keys: a 4096-bit container key (pk8/x509) and payload key (pem) per APEX, named after it.
make_key4096=$(mktemp); sed 's/2048/4096/g' "$E/development/tools/make_key" > "$make_key4096"; chmod +x "$make_key4096"
apex_args=()
while read -r apex; do
	key=$K/apex/${apex%.apex}
	mkdir -p "$K/apex"
	if [[ ! -f $key.pk8 ]]; then
		yes "" | "$make_key4096" "$key" "$subject" >/dev/null 2>&1 || true
		openssl pkcs8 -in "$key.pk8" -inform DER -nocrypt -out "$key.pem"
		chmod 600 "$key".pk8 "$key".pem
	fi
	apex_args+=(--extra_apks "$apex=$key" --extra_apex_payload_key "$apex=$key.pem")
done < <(unzip -p "$tf" META/apexkeys.txt | sed -n 's/^name="\([^"]*\)".*/\1/p' | sort -u)
rm -f "$make_key4096"
echo "APEX keys: $((${#apex_args[@]} / 4))"

signed=$work/signed-target_files.zip
# From the tree root: apkcerts gives APKs inside APEXes (AdServices...) their own keys as
# source-relative paths.
cd "$E"
# A finished signed target-files is reused (it is only renamed into place on success).
if [[ -f $signed && $signed -nt $tf ]]; then
	echo "reusing $signed"
else
sign_target_files_apks -o -d "$K" \
	--avb_vbmeta_key "$K/avb.pem" --avb_vbmeta_algorithm SHA256_RSA4096 \
	--avb_vbmeta_system_key "$K/avb.pem" --avb_vbmeta_system_algorithm SHA256_RSA4096 \
	--avb_recovery_key "$K/avb.pem" --avb_recovery_algorithm SHA256_RSA4096 \
	"${apex_args[@]}" "$tf" "$signed.tmp" > "$work/sign.log" 2>&1 || { tail -20 "$work/sign.log"; exit 1; }
mv "$signed.tmp" "$signed"
fi
echo "signed target-files: $signed"

ota_from_target_files -k "$K/releasekey" "$signed" "$work/$name.zip" > "$work/ota.log" 2>&1 || { tail -20 "$work/ota.log"; exit 1; }
echo "OTA: $work/$name.zip"

# Fastboot package: images from the signed target-files, plus a full super.img.
img=$work/images
rm -rf "$img"; mkdir -p "$img"
img_from_target_files "$signed" "$work/img.zip" > "$work/img.log" 2>&1 || { tail -20 "$work/img.log"; exit 1; }
unzip -q -o "$work/img.zip" -d "$img"
if [[ ! -f $img/super.img ]]; then
	build_super_image "$signed" "$img/super.img" > "$work/super.log" 2>&1 || { tail -20 "$work/super.log"; exit 1; }
fi
# Keep what flash-dizi.sh writes; the logical partition images live inside super.img.
( cd "$img" && ls | grep -vxE 'boot.img|vendor_boot.img|dtbo.img|vbmeta.img|vbmeta_system.img|recovery.img|super.img|android-info.txt' | xargs -r rm -f )
head -c 8192 /dev/zero > "$img/misc.img"
cp "$DIZI_ROOT/release/flash-dizi.sh" "$DIZI_ROOT/release/INSTALL.md" "$img/"
( cd "$img" && sha256sum ./*.img > SHA256SUMS )
( cd "$img" && zip -q -r "$work/$name-fastboot.zip" . )
# The usual Evolution X install flashes these four, then sideloads the zip in recovery.
for f in boot.img dtbo.img vendor_boot.img recovery.img; do cp "$img/$f" "$work/$f"; done
( cd "$work" && sha256sum "$name.zip" "$name-fastboot.zip" boot.img dtbo.img vendor_boot.img recovery.img > "$name.sha256" )
rm -f "$work/img.zip"
ls -la "$work"
