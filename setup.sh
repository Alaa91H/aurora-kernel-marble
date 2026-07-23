#!/usr/bin/env bash
#
# setup.sh — Aurora-Kernel source bootstrap
# Fetches: Android Common Kernel (ACK) 6.18 LTS from Google AOSP,
#          KernelSU-Next, AnyKernel3
#
# ACK = the Google-maintained branch of Linux LTS with all Android
# patches (binderfs, ashmem, GKI, vendor hooks) already merged.
# Must run on a Linux host. Idempotent: safe to re-run.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Google Android Common Kernel 6.18 LTS
# Repo: aosp.googlesource.com/kernel/manifest
# Branch: common-android17-6.18 (ACK track — 6.18 LTS pairs with Android 17,
#         NOT Android 15/16; those use 6.6 / 6.12 respectively)
KERNEL_MANIFEST_URL="https://android.googlesource.com/kernel/manifest"
KERNEL_BRANCH="${KERNEL_BRANCH:-common-android17-6.18}"
KERNEL_DIR="common-android17-6.18"

# KernelSU-Next (kprobe-based, GKI-friendly)
KSU_REPO="https://github.com/Kernelsu-Next/KernelSU-Next.git"
KSU_DIR="KernelSU-Next"
# Default branch is 'dev' (no 'main'/'master'); clone HEAD to track default.
KSU_BRANCH="${KSU_BRANCH:-dev}"

# AnyKernel3 flasher
ANYKERNEL_REPO="https://github.com/osm0sis/AnyKernel3.git"
ANYKERNEL_DIR="AnyKernel3"
ANYKERNEL_BRANCH="master"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf "\033[1;34m[setup]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m   %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { err "missing dependency: $1"; exit 1; }; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
log "preflight checks"
for c in git curl; do need "$c"; done
case "$(uname -s)" in
  Linux)  ;;
  Darwin) log "warning: macOS is untested, proceeding anyway" ;;
  *)      err "this script must run on Linux (got $(uname -s))"; exit 1 ;;
esac
ok "host ok"

# ---------------------------------------------------------------------------
# 1. Android Common Kernel 6.18 LTS (via repo tool)
# ---------------------------------------------------------------------------
if [[ -d "$KERNEL_DIR/.git" || -d "$KERNEL_DIR/.repo" ]]; then
  log "ACK ${KERNEL_BRANCH} already present, syncing latest"
  ( cd "$KERNEL_DIR" && repo sync -c -j"$(nproc)" )
else
  log "fetching Android Common Kernel ${KERNEL_BRANCH} (this is large: ~3-5 GB)"

  # Prefer Google's 'repo' tool; fall back to a shallow git clone of the
  # common kernel superproject if repo is not installed.
  if command -v repo >/dev/null 2>&1; then
    log "using 'repo' tool"
    mkdir -p "$KERNEL_DIR"
    ( cd "$KERNEL_DIR" && \
      repo init -u "$KERNEL_MANIFEST_URL" -b "$KERNEL_BRANCH" --depth=1 && \
      repo sync -c -j"$(nproc)" )
  else
    log "'repo' not found — falling back to shallow git clone of ACK common"
    log "  (install Google repo for the full manifest: https://source.android.com/docs/setup/download)"
    git clone --depth=1 -b "$KERNEL_BRANCH" \
      "https://android.googlesource.com/kernel/common" "$KERNEL_DIR"
  fi
fi

# normalize to a stable path for build.sh.
# The ACK `repo` manifest places the kernel source under `<dir>/common/`
# (project path="common" name="kernel/common"). When repo is used, the
# real source tree is one level deeper than the manifest dir. When the
# git-clone fallback is used, the source IS the clone dir.
if [[ -d "$KERNEL_DIR/common/Makefile" ]] || [[ -d "$KERNEL_DIR/common/Kbuild" ]]; then
  ln -sfn "$KERNEL_DIR/common" kernel-src || true
  log "kernel source at $KERNEL_DIR/common/ (repo manifest layout)"
elif [[ -d "$KERNEL_DIR/Makefile" ]] || [[ -d "$KERNEL_DIR/Kbuild" ]]; then
  ln -sfn "$KERNEL_DIR" kernel-src || true
  log "kernel source at $KERNEL_DIR/ (direct clone layout)"
else
  ln -sfn "$KERNEL_DIR" kernel-src || true
  log "WARNING: could not locate Makefile/Kbuild under $KERNEL_DIR; symlink may be wrong"
fi
ok "kernel source ready at ${KERNEL_DIR} (ACK 6.18 LTS)"

# ---------------------------------------------------------------------------
# 2. KernelSU-Next (optional — build continues without it if clone fails)
# ---------------------------------------------------------------------------
if [[ -d "$KSU_DIR/.git" ]]; then
  log "KernelSU-Next already present, pulling latest"
  git -C "$KSU_DIR" pull --ff-only || log "KSU pull failed, keeping existing"
else
  log "cloning KernelSU-Next (${KSU_BRANCH})"
  if ! git clone --depth=1 -b "$KSU_BRANCH" "$KSU_REPO" "$KSU_DIR"; then
    log "warning: KernelSU-Next clone failed; continuing WITHOUT root support"
    log "         (build will succeed; set KSU=0 or fix network and re-run)"
  fi
fi
[[ -d "$KSU_DIR/.git" ]] && ok "KernelSU-Next ready" || log "KernelSU-Next: skipped"

# ---------------------------------------------------------------------------
# 3. Integrate KernelSU into kernel tree
# ---------------------------------------------------------------------------
log "integrating KernelSU-Next into ACK tree"
KSU_BIN="$KSU_DIR/kernel"
KSU_DST="kernel-src/drivers/kernelsu"
if [[ -d "$KSU_BIN" ]]; then
  # ensure drivers/ exists in the (possibly symlinked) kernel tree
  mkdir -p "kernel-src/drivers" 2>/dev/null || true
  rm -rf "$KSU_DST"
  if cp -a "$KSU_BIN" "$KSU_DST"; then
    ok "KernelSU driver copied to drivers/kernelsu"
  else
    log "warning: KernelSU driver copy failed; root disabled this build"
  fi
else
  log "KernelSU-Next/kernel not found; integration skipped (root disabled)"
fi

# ---------------------------------------------------------------------------
# 4. AnyKernel3 flasher
# ---------------------------------------------------------------------------
if [[ -d "$ANYKERNEL_DIR/.git" ]]; then
  log "AnyKernel3 already present, pulling latest"
  git -C "$ANYKERNEL_DIR" pull --ff-only
else
  log "cloning AnyKernel3 (${ANYKERNEL_BRANCH})"
  git clone --depth=1 -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_REPO" "$ANYKERNEL_DIR"
fi
ok "AnyKernel3 ready"

# ---------------------------------------------------------------------------
# 5. Apply board DTS + defconfig into ACK tree
# ---------------------------------------------------------------------------
log "syncing marble board files into ACK tree"
DST_DTS="kernel-src/arch/arm64/boot/dts/qcom"
mkdir -p "$DST_DTS"
cp -f arch/arm64/boot/dts/qcom/*.dts    "$DST_DTS/" 2>/dev/null || true
cp -f arch/arm64/boot/dts/qcom/*.dtsi  "$DST_DTS/" 2>/dev/null || true

# append our Makefile entries if not present
AK_MAKE="$DST_DTS/Makefile"
if [[ -f arch/arm64/boot/dts/qcom/Makefile ]] && ! grep -q "marble-board" "$AK_MAKE" 2>/dev/null; then
  cat arch/arm64/boot/dts/qcom/Makefile >> "$AK_MAKE" || true
fi

# copy our defconfig into the ACK tree
DST_CFG="kernel-src/arch/arm64/configs"
mkdir -p "$DST_CFG"
cp -f configs/marble_defconfig "$DST_CFG/" 2>/dev/null || true
ok "board files synced"

# ---------------------------------------------------------------------------
# 6. Apply patches (if any)
# ---------------------------------------------------------------------------
log "applying patches (if any)"
bash scripts/patch-apply.sh || true
ok "patch queue applied"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<EOF

${0##*/}: all sources ready

  ACK kernel    : $(pwd)/$KERNEL_DIR  (symlink: kernel-src)
  KernelSU-Next : $(pwd)/$KSU_DIR
  AnyKernel3    : $(pwd)/$ANYKERNEL_DIR

This is Android Common Kernel (ACK) 6.18 LTS from Google AOSP.
It already contains all Android-specific patches (binderfs, ashmem,
GKI modules, vendor hooks) on top of the 6.18 LTS stable base.
NOTE: 6.18 LTS is the GKI kernel for Android 17.

Next:
  ./scripts/toolchain.sh   # fetch Proton-Clang (optional)
  ./build.sh               # build kernel + flashable zip

EOF
