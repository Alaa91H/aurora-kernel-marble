# ADR 0002: No Placebo Tuning

**Status:** Accepted
**Date:** 2026-07-23

## Problem

Custom kernels commonly ship "tuning" sysctls and CONFIG options that
either do nothing (dead options), duplicate mainline behavior, or are
copied from other kernels without verification. These create a false sense
of optimization and obscure real performance characteristics.

## Alternatives Considered

1. **Inherit popular sysctls from other custom kernels** — easy, but
   propagates unverified settings that may not apply to 6.18's scheduler
   or memory subsystem.
2. **Ship every plausible tuning knob** — maximizes perceived value, but
   violates the "measured optimization only" principle.
3. **Ship only verified, functional tuning** — harder, but honest.

## Decision

Adopt a **zero placebo policy**: every sysctl and CONFIG option must be
verified to actually affect behavior on Linux 6.18, with the mechanism
documented. Dead configurations and unverified parameters are removed.

## Rationale

- Linux 6.18's EEVDF scheduler behaves differently from CFS; sysctls
  tuned for CFS may be inert or harmful.
- zRAM/zswap/DAMON have real, measurable effects; placebo settings dilute
  them.
- Users deserve to know *why* each setting exists.

## Future Impact

The runtime tuning script (`aurora-tune.sh`) must carry a comment per
sysctl explaining the mechanism. Any setting added without a documented
mechanism is subject to removal during review.
