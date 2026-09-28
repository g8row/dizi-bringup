#!/bin/bash
# Dump every named partition (except userdata and scratch areas) from the
# rooted stock tablet to stock/backup/, verifying sha256 on both ends.
set -euo pipefail
. "$(dirname "$0")/env"
out=$DIZI_ROOT/stock/backup
mkdir -p "$out"
skip='^(userdata|testparti|logdump|rawdump|sd[a-z])$'

"$(dirname "$0")/remote.sh" adb wait-for-device
"$(dirname "$0")/remote.sh" adb shell \
	'su -c "for p in /dev/block/by-name/*; do echo \${p##*/}; done"' |
	tr -d '\r' | grep -Ev "$skip" > "$out/list.txt"

while read -r name; do
	img=$out/$name.img
	if [[ -s $img && -s $img.sha256 ]]; then
		continue
	fi
	ok=
	for try in 1 2 3; do
		echo ">> $name (try $try)"
		"$(dirname "$0")/remote.sh" adb wait-for-device </dev/null
		"$(dirname "$0")/remote.sh" adb exec-out \
			"su -c 'dd if=/dev/block/by-name/$name bs=4M 2>/dev/null'" > "$img.tmp" </dev/null || continue
		remote=$("$(dirname "$0")/remote.sh" adb shell \
			"su -c 'sha256sum /dev/block/by-name/$name'" </dev/null | awk '{print $1}') || continue
		local_sum=$(sha256sum "$img.tmp" | awk '{print $1}')
		if [[ $remote == "$local_sum" ]]; then
			ok=1
			break
		fi
		echo "!! checksum mismatch for $name" >&2
	done
	if [[ -z $ok ]]; then
		rm -f "$img.tmp"
		exit 1
	fi
	mv "$img.tmp" "$img"
	echo "$local_sum  $name.img" > "$img.sha256"
done < "$out/list.txt"
echo "backup complete: $(wc -l < "$out/list.txt") partitions"
