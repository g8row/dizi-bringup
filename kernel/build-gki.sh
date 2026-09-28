#!/bin/bash
# Stage (a) of research/kernel-source.md: LineageOS sm7435 Image with plain
# gki_defconfig and the stock kernel's compiler (clang r416183b, LTO+CFI).
set -uo pipefail
K=$(cd "$(dirname "$0")" && pwd)
export PATH=$K/clang-r416183b/bin:$PATH
O=$K/out-gki
args=(-C "$K/lineage" O="$O" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- -j48)
make "${args[@]}" gki_defconfig && make "${args[@]}" Image modules_prepare vmlinux
echo "exit=$?"
