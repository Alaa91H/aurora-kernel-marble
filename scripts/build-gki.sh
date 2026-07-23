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
KERNEL_ROOT="${KERNEL_ROOT:-$ROOT/kernel-root}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
CFG_DIR="$ROOT/configs"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
DEFCONFIG="${DEFCONFIG:-marble_defconfig}"
ARCH=arm64
JOBS="$(nproc 2>/dev/null || echo 8)"

log()  { printf "\033[1;34m[gki]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Toolchain — source the env written by toolchain.sh (system clang preferred)
# ---------------------------------------------------------------------------
TC_ENV="$ROOT/toolchains/toolchain.env"
if [[ ! -f "$TC_ENV" ]]; then
  log "no toolchain.env; bootstrapping toolchain"
  bash scripts/toolchain.sh
fi
if [[ -f "$TC_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$TC_ENV"
fi
TC_BIN="${TC_BIN:-$ROOT/toolchains/proton-clang/bin}"

# resolve the actual clang binary (handles clang-17 symlink names)
CLANG_BIN="${CC:-clang}"
if ! command -v "$CLANG_BIN" >/dev/null 2>&1 && [[ -x "$TC_BIN/$CLANG_BIN" ]]; then
  CLANG_BIN="$TC_BIN/$CLANG_BIN"
fi
if ! command -v "$CLANG_BIN" >/dev/null 2>&1; then
  err "clang not available; run ./scripts/toolchain.sh"
fi

# point LD at lld (prefer same dir as clang, else PATH)
LD_BIN="ld.lld"
command -v "$LD_BIN" >/dev/null 2>&1 || { [[ -x "$TC_BIN/$LD_BIN" ]] && LD_BIN="$TC_BIN/$LD_BIN"; }

export CC="$CLANG_BIN"
export LD="$LD_BIN"
export LLVM_AR="${LLVM_AR:-llvm-ar}";        command -v "$LLVM_AR" >/dev/null 2>&1 || LLVM_AR="$TC_BIN/llvm-ar"
export LLVM_NM="${LLVM_NM:-llvm-nm}";        command -v "$LLVM_NM" >/dev/null 2>&1 || LLVM_NM="$TC_BIN/llvm-nm"
export LLVM_OBJCOPY="${LLVM_OBJCOPY:-llvm-objcopy}"; command -v "$LLVM_OBJCOPY" >/dev/null 2>&1 || LLVM_OBJCOPY="$TC_BIN/llvm-objcopy"
export LLVM_OBJDUMP="${LLVM_OBJDUMP:-llvm-objdump}"; command -v "$LLVM_OBJDUMP" >/dev/null 2>&1 || LLVM_OBJDUMP="$TC_BIN/llvm-objdump"
export LLVM_STRIP="${LLVM_STRIP:-llvm-strip}";       command -v "$LLVM_STRIP" >/dev/null 2>&1 || LLVM_STRIP="$TC_BIN/llvm-strip"
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
# 2. Build — prefer Bazel/kleaf (official ACK build system) if present.
#    Bazel runs from the manifest ROOT (kernel-root), not from common/.
#    The kleaf build target is //common:kernel_aarch64_dist.
# ---------------------------------------------------------------------------
BAZEL=""
# bazel linkfile lives at the manifest root
[[ -x "$KERNEL_ROOT/tools/bazel" ]] && BAZEL="$KERNEL_ROOT/tools/bazel"
# or on PATH
[[ -z "$BAZEL" ]] && command -v bazel >/dev/null 2>&1 && BAZEL="$(command -v bazel)"

if [[ -n "$BAZEL" ]]; then
  log "building GKI via Bazel/kleaf (official ACK method): $BAZEL"
  # kleaf: build the aarch64 GKI kernel + dist artifacts.
  # The default //common:kernel_aarch64_dist target uses the ACK
  # gki_aarch64_defconfig. Custom defconfig fragments are applied via
  # --kernel_build_defconfig_fragments=<path> once the base build works.
  ( cd "$KERNEL_ROOT" && \
    "$BAZEL" build //common:kernel_aarch64_dist \
      --config=fast --jobs "$JOBS" \
      2>&1 | tail -400 ) || {
    log "bazel build failed; falling back to raw make"
    BAZEL=""
  }
fi

if [[ -z "$BAZEL" ]]; then
  # ---------------------------------------------------------------------------
  # 2a. Raw make fallback — KERNEL_SRC points at common/ (has Makefile)
  # ---------------------------------------------------------------------------
  log "olddefconfig (raw make, src=$KERNEL_SRC)"
  make -C "$KERNEL_SRC" O="$OUT_DIR" LLVM=1 CC="$CC" LD="$LD" olddefconfig

  log "building GKI core (Image, modules, dtbs) — $JOBS jobs"
  make -C "$KERNEL_SRC" O="$OUT_DIR" LLVM=1 CC="$CC" LD="$LD" -j"$JOBS" \
    Image modules dtbs 2>&1 | tail -300
fi

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
