#!/bin/bash
# Build msm_drm.ko (MiCode vendor_opensource_display-drivers@ruan-u-oss) as an
# external module against the lineage GKI tree.
#   kobj/  : lineage tree, gki_defconfig + MiCode vendor/ruan_GKI.config, modules_prepare,
#            Module.symvers copied from ../out-gki (the Image we boot)
#   deps/stock-deps.symvers : synthesized from the stock prebuilt dependency modules
# Usage: build.sh <srcdir> [extra make args]
set -uo pipefail
K=/build/alex/dizi/kernel
D=$K/out-display
SRC=$(realpath "${1:-$D/src}"); shift || true
export PATH=$K/clang-r416183b/bin:$PATH
make -C $K/lineage O=$D/kobj ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- -j48 \
  M=$SRC KERNEL_SRC=$K/lineage DISPLAY_ROOT=$SRC MODNAME=msm_drm BOARD_PLATFORM=parrot CONFIG_DRM_MSM=m \
  KCFLAGS=-I$K/micode-ruan/drivers/input/touchscreen KBUILD_EXTRA_SYMBOLS=$D/deps/stock-deps.symvers "$@" modules
echo "exit=$?"
