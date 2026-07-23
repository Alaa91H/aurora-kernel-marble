#!/usr/bin/env bash
#
# scripts/vendor-fetch.sh — fetch the Qualcomm/Xiaomi vendor kernel tree
# for marble (SM7475 / Snapdragon 7+ Gen 2).
#
# Why: the Google ACK 'common' tree has NO SoC drivers (no display, no UFS,
# no modem, no audio). Real hardware boots from Qualcomm's 'msm-kernel'
# BSP which Xiaomi publishes per-device. We fetch that vendor tree and
# layer our Aurora defconfig + DTS on top, exactly as GKI intends:
#
#   GKI core  = common-android17-6.18 (common)    <- setup.sh
#   vendor    = msm-kernel marble (qualcomm)    <- this script
#   board     = our defconfig + DTS             <- configs/ + arch/
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ---------------------------------------------------------------------------
# Source trees
# ---------------------------------------------------------------------------
# IMPORTANT REALITY CHECK:
# Xiaomi's ONLY published marble kernel source is `marble-s-oss` on
# MiCode/Xiaomi_Kernel_OpenSource. It is Android 12 / 5.10-class — there is
# NO official marble tree on 6.18. Building on 6.18 therefore requires
# "mainlining": porting the 5.10 drivers to the 6.18 API, which is real
# engineering work, not a one-shot script.
#
# This script fetches the closest available sources for reference/porting:
VENDOR_DIR="${VENDOR_DIR:-vendor-msm}"

# Primary: Xiaomi official marble source (5.10-based, for porting reference)
XIAOMI_URL="https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git"
XIAOMI_BRANCH="${XIAOMI_BRANCH:-marble-s-oss}"

# Fallback: CodeLinaro msm-kernel (Qualcomm BSP; the 6.6 track is the
# nearest upstream-backed Qualcomm tree — no 6.18 SM7475 BSP exists yet)
CLO_URL="https://git.codelinaro.org/clo/qsdk/oss/kernel/linux-msm.git"
CLO_BRANCH="${CLO_BRANCH:-third_party/kernels/msm-6.6/qsdk/scar.msm-6.6}"

log()  { printf "\033[1;34m[vendor]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; }

# ---------------------------------------------------------------------------
# Fetch
# ---------------------------------------------------------------------------
fetch_via_git() {
  local url="$1" branch="$2"
  log "fetching vendor tree via git: $url ($branch)"
  if [[ -d "$VENDOR_DIR/.git" ]]; then
    git -C "$VENDOR_DIR" fetch --depth=1 origin "$branch"
    git -C "$VENDOR_DIR" checkout "$branch"
  else
    git clone --depth=1 -b "$branch" "$url" "$VENDOR_DIR"
  fi
}

if [[ -d "$VENDOR_DIR" ]]; then
  log "vendor tree already present: $VENDOR_DIR"
else
  if ! fetch_via_git "$XIAOMI_URL" "$XIAOMI_BRANCH"; then
    log "Xiaomi marble-s-oss unreachable, falling back to CodeLinaro msm-kernel"
    fetch_via_git "$CLO_URL" "$CLO_BRANCH" || \
      err "could not fetch vendor tree; offline builds must supply $VENDOR_DIR manually"
  fi
fi
ok "vendor tree ready at $VENDOR_DIR"

# ---------------------------------------------------------------------------
# Identify the vendor defconfig we'll merge FROM (for driver symbols)
# ---------------------------------------------------------------------------
log "locating vendor defconfig for marble"
VENDOR_CFG=""
for c in \
  "$VENDOR_DIR/arch/arm64/configs/marble_defconfig" \
  "$VENDOR_DIR/arch/arm64/configs/vendor/marble-qgki.config" \
  "$VENDOR_DIR/arch/arm64/configs/sm7475-marble_defconfig"; do
  if [[ -f "$c" ]]; then VENDOR_CFG="$c"; break; fi
done
if [[ -n "$VENDOR_CFG" ]]; then
  ok "vendor defconfig: $VENDOR_CFG"
  # record for config-merge.sh to consume
  printf '%s\n' "$VENDOR_CFG" > .vendor_cfg_path
else
  err "no vendor defconfig found under $VENDOR_DIR/arch/arm64/configs"
  err "the build will proceed with GKI-only symbols; expect vendor module link errors"
fi

# ---------------------------------------------------------------------------
# Report topology for the merge step
# ---------------------------------------------------------------------------
cat <<EOF

${0##*/}: vendor tree ready

  vendor dir : $(pwd)/$VENDOR_DIR
  vendor cfg : ${VENDOR_CFG:-<none>}

REALITY CHECK:
  The fetched vendor tree is the closest available reference source.
  Xiaomi's official marble source (marble-s-oss) is Android 12 / 5.10-class.
  Porting to 6.18 requires mainlining: adapting 5.10 driver APIs to 6.18
  (clock, pinctrl, iommu, interconnect bindings all changed across 5.10->6.18).
  This is the genuinely hard part — not a one-shot script.

  The GKI build (build.sh) will now:
  1. build the GKI core from common-android17-6.18
  2. compile vendor modules from $VENDOR_DIR against the GKI vmlinux.symvers
     (NOTE: a 5.10 driver tree will NOT compile cleanly against 6.18 without
      mainlining patches — expect link errors; this is expected at this stage)
  3. package Image (GKI) + vendor_dlkm (modules) + dtbo into boot.img

Next: ./build.sh

EOF
