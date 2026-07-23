#!/usr/bin/env bash
#
# scripts/build-vendor-modules.sh — build vendor (out-of-tree) modules against
# the GKI core produced by build-gki.sh.
#
# This is the GKI way: the generic kernel stays pristine; SoC drivers
# (display, UFS, audio, modem, camera) are built as loadable .ko modules
# from the Qualcomm/Xiaomi vendor tree and packed into vendor_dlkm.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KERNEL_SRC="${KERNEL_SRC:-$ROOT/kernel-src}"
VENDOR_DIR="${VENDOR_DIR:-$ROOT/vendor-msm}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
ARCH=arm64
JOBS="$(nproc 2>/dev/null || echo 8)"

log()  { printf "\033[1;34m[vendor]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

[[ -d "$VENDOR_DIR" ]] || err "vendor tree missing. Run scripts/vendor-fetch.sh first."
[[ -f "$DIST_DIR/vmlinux.symvers" ]] || err "GKI not built. Run scripts/build-gki.sh first."

# ---------------------------------------------------------------------------
# Toolchain — source the env written by toolchain.sh (same as GKI build)
# ---------------------------------------------------------------------------
TC_ENV="$ROOT/toolchains/toolchain.env"
[[ -f "$TC_ENV" ]] && source "$TC_ENV"
TC_BIN="${TC_BIN:-$ROOT/toolchains/proton-clang/bin}"
CLANG_BIN="${CC:-clang}"
command -v "$CLANG_BIN" >/dev/null 2>&1 || [[ -x "$TC_BIN/$CLANG_BIN" ]] && CLANG_BIN="$TC_BIN/$CLANG_BIN"
command -v "$CLANG_BIN" >/dev/null 2>&1 || err "clang not available; run scripts/toolchain.sh"
export CC="$CLANG_BIN"
export LD="${LD:-ld.lld}"
export LLVM_AR="${LLVM_AR:-llvm-ar}"
export LLVM_NM="${LLVM_NM:-llvm-nm}"
export LLVM_OBJCOPY="${LLVM_OBJCOPY:-llvm-objcopy}"
export LLVM_OBJDUMP="${LLVM_OBJDUMP:-llvm-objdump}"
export LLVM_STRIP="${LLVM_STRIP:-llvm-strip}"
export ARCH
export PATH="$TC_BIN:$PATH"
export KBUILD_BUILD_USER=aurora
export KBUILD_BUILD_HOST=marble
export KCFLAGS="-O3 -pipe -fno-plt"

# Point vendor build at the GKI output (vmlinux, Module.symvers, generated headers)
VENDOR_OUT="$ROOT/out/vendor"
mkdir -p "$VENDOR_OUT"

# ---------------------------------------------------------------------------
# Prepare vendor module list (which .ko to build)
# ---------------------------------------------------------------------------
# The vendor tree ships modules_list at vendor/..., else build everything
# that is marked =m in the vendor defconfig.
MODULES_LIST="${MODULES_LIST:-$VENDOR_DIR/vendor/modules.list}"
if [[ ! -f "$MODULES_LIST" ]]; then
  log "no vendor/modules.list; building all modules from vendor tree"
  MODULES_LIST=""
fi

# ---------------------------------------------------------------------------
# Build vendor modules out-of-tree against the GKI kernel
# ---------------------------------------------------------------------------
log "building vendor modules against GKI core ($JOBS jobs)"

# Vendor trees expect KBUILD_EXTMOD pointing at their source root.
# We pass M=<vendor module dirs> and the GKI build dir as the kernel to build against.
make -C "$KERNEL_SRC" O="$OUT_DIR" LLVM=1 -j"$JOBS" \
  M="$VENDOR_DIR" \
  modules 2>&1 | tail -200 || {
    err "vendor module build failed"
    err "common causes: vendor symbol not in GKI KMI list, or GKI defconfig missing a CONFIG"
    err "fix: add the missing CONFIG to configs/marble_defconfig or fragments/*.config, rebuild GKI, retry"
    exit 1
  }

# ---------------------------------------------------------------------------
# Stage modules into dist/vendor_dlkm
# ---------------------------------------------------------------------------
VDLKM="$DIST_DIR/vendor_dlkm"
rm -rf "$VDLKM"
mkdir -p "$VDLKM/lib/modules"

# find all built .ko from vendor tree + GKI tree
mapfile -t KOS < <(find "$VENDOR_OUT" "$OUT_DIR" -name '*.ko' 2>/dev/null)
if [[ ${#KOS[@]} -eq 0 ]]; then
  log "no vendor modules produced (GKI-only build)"
else
  log "staging ${#KOS[@]} modules"
  for ko in "${KOS[@]}"; do
    cp -f "$ko" "$VDLKM/lib/modules/"
  done
fi

# depmod against the staged tree
KVER=$(make -s -C "$KERNEL_SRC" O="$OUT_DIR" kernelrelease 2>/dev/null || echo "6.18.0")
depmod -b "$VDLKM" -ae "$KVER" 2>/dev/null || true

# modules.load + modules.dep shipped for the init script
find "$VDLKM/lib/modules" -name '*.ko' -printf '%f\n' | sort > "$VDLKM/modules.load"
ok "vendor_dlkm staged: $VDLKM (${#KOS[@]} modules, kernel $KVER)"
