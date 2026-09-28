#!/bin/bash
# In-tree GKI modules, for Module.symvers (the kernel's exported symbol CRCs).
set -uo pipefail
K=$(cd "$(dirname "$0")" && pwd)
export PATH=$K/clang-r416183b/bin:$PATH
make -C "$K/lineage" O="$K/out-gki" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- -j48 modules
echo "exit=$?"
