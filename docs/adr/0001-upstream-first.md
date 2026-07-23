# ADR 0001: Upstream-First Engineering

**Status:** Accepted
**Date:** 2026-07-23

## Problem

Custom Android kernels accumulate downstream-only patches that diverge
from mainline Linux, creating unmaintainable technical debt that makes
each LTS migration increasingly expensive.

## Alternatives Considered

1. **Full downstream BSP fork** (Qualcomm/Xiaomi vendor trees) — fastest
   to boot, but diverges thousands of commits from mainline; LTS migrations
   become rewrite-level efforts.
2. **Selective cherry-picking** from vendor trees into ACK — moderate
   divergence, but still accumulates untraceable patches.
3. **Upstream-first with minimal vendor glue** — ACK as the base, vendor
   code confined to `drivers/soc/`, DTS, and loadable modules.

## Decision

Adopt **upstream-first engineering**: build on Android Common Kernel
(ACK), restrict vendor-specific code to tightly scoped integration layers
(SoC drivers, DeviceTree, firmware loaders), and submit general fixes
upstream where feasible.

## Rationale

- ACK already contains all Android-required patches (binderfs, ashmem,
  GKI, vendor hooks) on top of mainline LTS.
- Vendor divergence is confined to `drivers/soc/qcom/` and DTS, not core
  subsystems.
- LTS migrations require only updating the ACK branch + re-porting the
  vendor glue, not a full re-merge.

## Future Impact

Future LTS upgrades (6.6 → 6.12 → 6.18) require updating `setup.sh`'s
`KERNEL_BRANCH` and re-applying the vendor mainlining patches, rather than
re-basing an entire fork.
