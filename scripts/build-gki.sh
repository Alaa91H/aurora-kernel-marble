#!/usr/bin/env bash
#
# scripts/build-gki.sh — build the GKI core kernel from ACK 6.18 LTS
#
# Produces:
#   out/Image                 (the generic kernel image, flashed to boot)
#   out/vmlinux.symvers       (Module.symvers — required to build vendor modules)
#   out/modules.builtin       (built-in modules list)
#   out/dtbo.img              (our marble dtbo, from arch/.../dts/qcom)
#
# This script ONLY builds the GKI core. Vendor modules are built separately
# by build-vendor-modules.sh against the vmlinux.symvers produced here.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KERNEL_SRC="${KERNEL_SRC:-$ROOT/kernel-src}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
DEFCONFIG="${DEFCONFIG:-marble_defconfig}"
ARCH=arm64
JOBS="$(nproc 2>/dev/null || echo 8)"

log()  { printf "\033[1;34m[gki]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------
TC_BIN="${TC_BIN:-$ROOT/toolchains/proton-clang/bin}"
[[ -x "$TC_BIN/clang" ]] || { log "proton-clang missing; bootstrapping"; bash scripts/toolchain.sh; }
[[ -x "$TC_BIN/clang" ]] || err "clang not available"

export CC="$TC_BIN/clang"
export LD="$TC_BIN/ld.lld"
export LLVM_AR="$TC_BIN/llvm-ar"
export LLVM_NM="$TC_BIN/llvm-nm"
export LLVM_OBJCOPY="$TC_BIN/llvm-objcopy"
export LLVM_OBJDUMP="$TC_BIN/llvm-objdump"
export LLVM_STRIP="$TC_BIN/llvm-strip"
export ARCH
export PATH="$TC_BIN:$PATH"
export KBUILD_BUILD_USER=aurora
export KBUILD_BUILD_HOST=marble

# Clang optimization flags
export KCFLAGS="-O3 -pipe -fno-plt -fmacro-prefix-map=$KERNEL_SRC=."
export LDFLAGS="-fuse-ld=lld --icf=all"

mkdir -p "$OUT_DIR" "$DIST_DIR"

# ---------------------------------------------------------------------------
# 1. Merge config fragments
# ---------------------------------------------------------------------------
log "merging defconfig + fragments"
bash scripts/config-merge.sh

# ---------------------------------------------------------------------------
# 2. olddefconfig to settle symbol dependencies
# ---------------------------------------------------------------------------
log "olddefconfig"
make -C "$KERNEL_SRC" O="$OUT_DIR" LLVM=1 olddefconfig

# ---------------------------------------------------------------------------
# 3. Build the GKI image + modules + dtbs
# ---------------------------------------------------------------------------
log "building GKI core (Image, modules, dtbs) — $JOBS jobs"
make -C "$KERNEL_SRC" O="$OUT_DIR" LLVM=1 -j"$JOBS" \
  Image modules dtbs 2>&1 | tail -300

# ---------------------------------------------------------------------------
# 4. Validate artifacts
# ---------------------------------------------------------------------------
IMG="$OUT_DIR/arch/arm64/boot/Image"
[[ -f "$IMG" ]] || err "GKI Image not produced"

# Module.symvers is the contract for vendor modules
SYMVERS="$OUT_DIR/Module.symvers"
[[ -f "$SYMVERS" ]] || err "Module.symvers missing — cannot build vendor modules"

# built-in modules list (for initramfs / depmod)
[[ -f "$OUT_DIR/modules.builtin" ]] || err "modules.builtin missing"

ok "GKI Image: $IMG"
ok "symvers:  $SYMVERS"

# ---------------------------------------------------------------------------
# 5. Copy to DIST_DIR for the packaging step
# ---------------------------------------------------------------------------
cp -f "$IMG"                                      "$DIST_DIR/Image"
cp -f "$SYMVERS"                                   "$DIST_DIR/vmlinux.symvers"
cp -f "$OUT_DIR/modules.builtin"                   "$DIST_DIR/modules.builtin"
cp -f "$OUT_DIR/modules.builtin.modinfo"           "$DIST_DIR/modules.builtin.modinfo" 2>/dev/null || true
cp -f "$OUT_DIR/System.map"                        "$DIST_DIR/System.map" 2>/dev/null || true

# dtbo from our marble DTS
DTBO="$OUT_DIR/arch/arm64/boot/dtbo.img"
[[ -f "$DTBO" ]] && cp -f "$DTBO" "$DIST_DIR/dtbo.img"

# individual dtbs (for inspection)
mkdir -p "$DIST_DIR/dtbs"
cp -f "$OUT_DIR/arch/arm64/boot/dts/qcom/marble-board.dtb" "$DIST_DIR/dtbs/" 2>/dev/null || true

ok "dist artifacts in $DIST_DIR"
