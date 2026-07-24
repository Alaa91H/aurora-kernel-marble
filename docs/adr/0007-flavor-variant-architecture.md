# ADR 0007: Hierarchical Flavor / Variant Architecture

**Status:** Accepted
**Date:** 2026-07-24

## Problem

Supporting multiple platforms (AOSP, HyperOS), root solutions (NoRoot,
KernelSU, KernelSU-Next, APatch), and build profiles (Production, Gaming,
Battery, Development) traditionally requires maintaining separate kernel
branches per combination — leading to exponential branch count and
unmaintainable technical debt.

## Alternatives Considered

1. **Separate branches per variant** — `aurora-aosp-ksu`,
   `aurora-hyperos-noroot`, etc. Exponential branches, merge hell.
2. **Separate defconfigs per variant** — `marble_aosp_ksu_defconfig`,
   etc. Duplicated config, drift between files.
3. **Hierarchical flavor merge** — one base defconfig + layered config
   fragments selected by a `FLAVOR="platform-root-profile"` env var.

## Decision

Adopt the **hierarchical flavor merge** architecture:

```
Core (marble_defconfig + fragments/*.config)
  ↓
Platform Layer  (configs/flavors/platform/{aosp,hyperos}.config)
  ↓
Root Layer      (configs/flavors/root/{noroot,ksu,ksunext,apatch}.config)
  ↓
Profile Layer   (configs/flavors/profile/{production,gaming,battery,development}.config)
  ↓
Final .config
```

A single `FLAVOR="platform-root-profile"` env var controls which fragments
are merged. Examples:
- `FLAVOR=aosp-noroot-production` (default, safest)
- `FLAVOR=hyperos-ksunext-battery` (HyperOS, KSU-Next, battery saver)
- `FLAVOR=aosp-apatch-gaming` (AOSP, APatch, gaming profile)

## Rationale

- **No branch explosion**: 2 platforms × 4 roots × 4 profiles = 32 variants
  from ONE source tree.
- **No config duplication**: each concern lives in exactly one fragment.
- **Composable**: any platform × root × profile combination works.
- **CI matrix**: GitHub Actions `strategy.matrix` builds all variants
  automatically.
- **Maintainable**: adding a new root solution = one new file in
  `configs/flavors/root/`.

## Future Impact

- `config-merge.sh` parses `FLAVOR` and selects the 3 layer files.
- `build.sh` exports `FLAVOR`, `VERSION` (includes flavor), `KSU` flag.
- CI builds a matrix of 6 default flavors on every push.
- Users select their variant by downloading the appropriately-named zip:
  `aurora-kernel-marble-6.18-ack-aosp-ksunext-production-<sha>.zip`
