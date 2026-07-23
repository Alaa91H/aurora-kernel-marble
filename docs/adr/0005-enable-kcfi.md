# ADR 0005: Enforce Kernel Control Flow Integrity (KCFI)

**Status:** Accepted
**Date:** 2026-07-23

## Problem

Return-oriented programming (ROP) and branch-target hijacking remain
exploitable attack vectors. Indirect calls in the kernel can be
redirected to arbitrary functions, enabling privilege escalation.

## Alternatives Considered

1. **No CFI** — zero overhead, but leaves indirect calls unprotected.
2. **Clang CFI (`CONFIG_CFI_CLANG`)** — runtime indirect-call
   verification; measurable but small overhead (1-2% on macro benchmarks).
3. **KCFI (kernel CFI)** — the same Clang CFI but optimized for the kernel
   indirect-call pattern; lower overhead than full CFI.

## Decision

Enable **KCFI** (`CONFIG_CFI_CLANG=y`) in all production Aurora builds.
Development builds may set `CONFIG_CFI_PERMISSIVE=y` to log violations
without crashing.

## Rationale

- KCFI is the upstream-recommended CFI mode for ARM64 in 6.18.
- Overhead is within margin of error for mobile workloads per Google's
  GKI measurements.
- The spec mandates: "Never disable security features solely for benchmark
  gains."

## Future Impact

The defconfig must set `CONFIG_CFI_CLANG=y` and the build must use a
Clang toolchain (GCC does not support CFI). `CONFIG_CFI_PERMISSIVE=n`
for production.
