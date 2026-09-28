#!/bin/bash
# Phase 6 sources: LineageOS sm7435 kernel (+modules, devicetrees) and Xiaomi's dizi/ruan drop.
set -uo pipefail
cd "$(dirname "$0")"
clone() { [[ -d $2 ]] && { echo "have $2"; return; }; git clone -q --depth 1 -b "$3" "$1" "$2" && echo "cloned $2 ($(git -C "$2" log --oneline -1))"; }
clone https://github.com/LineageOS/android_kernel_xiaomi_sm7435 lineage lineage-23.2
clone https://github.com/LineageOS/android_kernel_xiaomi_sm7435-modules lineage-modules lineage-23.2
clone https://github.com/LineageOS/android_kernel_xiaomi_sm7435-devicetrees lineage-devicetrees lineage-23.2
clone https://github.com/MiCode/Xiaomi_Kernel_OpenSource micode-ruan ruan-u-oss
echo fetch done
