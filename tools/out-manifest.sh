#!/bin/bash
# Hash every installed file of a bench build, to diff two builds of the same device.
# Usage: out-manifest.sh <name> [device]  ->  logs/out-manifest/<device>-<name>.txt
# build.prop files are hashed with the lines that change on every build (dates, build
# numbers, fingerprints) filtered out, so only real content changes show.
set -euo pipefail
name=${1:?name}
DEVICE=${2:-${DEVICE:-dizi}}
. "$(dirname "$0")/env"
product_out=$DIZI_ROOT/evox/$DIZI_OUT_NAME/target/product/$DIZI_DEVICE
out=$DIZI_ROOT/logs/out-manifest/$DIZI_DEVICE-$name.txt
volatile='ro\.([a-z_]+\.)?build\.(date|host|id|fingerprint|version\.incremental|description|display\.id|thumbprint)|ro\.(lineage|evolution|modversion)|\.date(\.utc)?=|incremental'

mkdir -p "${out%/*}"
cd "$product_out"
{
	for part in system system_ext product vendor odm vendor_dlkm vendor_ramdisk recovery/root; do
		[[ -d $part ]] || continue
		find "$part" \( -type f -o -type l \) -print0 | sort -z | while IFS= read -r -d '' f; do
			if [[ -L $f ]]; then
				printf 'link %s %s\n' "$(readlink "$f")" "$f"
			elif [[ ${f##*/} == build.prop || ${f##*/} == *_build.prop || $f == */etc/prop.default ]]; then
				printf '%s %s\n' "$({ grep -vE "$volatile" "$f" || true; } | sha256sum | cut -c1-16)" "$f"
			else
				printf '%s %s\n' "$(sha256sum < "$f" | cut -c1-16)" "$f"
			fi
		done
	done
} > "$out"
echo "$out: $(wc -l < "$out") files"
