#!/system/bin/sh
#
# aurora-tune.sh — one-shot runtime tuner for marble
# Runs from init.aurora.rc on boot and from aurora-profile service on demand.
#
# Usage:
#   aurora-tune.sh [performance|battery|balanced]
#
set -u

PROFILE="${1:-balanced}"

p()  { # path value
    [ -e "$1" ] && echo "$2" > "$1" 2>/dev/null
}

cpu_each() { # callback per cpu
    for c in 0 1 2 3 4 5 6 7; do "$@" "$c"; done
}

# ---------------------------------------------------------------------------
# sysctl
# ---------------------------------------------------------------------------
apply_sysctl() {
    sysctl -q -p /system/etc/99-aurora-sysctl.conf 2>/dev/null \
        || sysctl -q -p /sbin/99-aurora-sysctl.conf 2>/dev/null \
        || true

    # VM swappiness (low for performance, higher for battery)
    case "$PROFILE" in
        performance) sysctl -q -w vm.swappiness=10 ;;
        battery)     sysctl -q -w vm.swappiness=140 ;;
        *)           sysctl -q -w vm.swappiness=100 ;;
    esac

    # kernel latency
    sysctl -q -w kernel.sched_latency_ns=10000000
    sysctl -q -w kernel.sched_min_granularity_ns=1000000
    sysctl -q -w kernel.sched_wakeup_granularity_ns=2000000
    sysctl -q -w kernel.sched_migration_cost=500000

    # network: BBR + fq
    sysctl -q -w net.core.default_qdisc=fq
    sysctl -q -w net.ipv4.tcp_congestion_control=bbr
    sysctl -q -w net.ipv4.tcp_fastopen=3
    sysctl -q -w net.ipv4.tcp_mtu_probing=1
    sysctl -q -w net.ipv4.tcp_slow_start_after_idle=0
    sysctl -q -w net.ipv4.tcp_no_metrics_save=1
    sysctl -q -w net.ipv4.tcp_rmem="4096 87380 67108864"
    sysctl -q -w net.ipv4.tcp_wmem="4096 65536 67108864"
    sysctl -q -w net.core.rmem_max=67108864
    sysctl -q -w net.core.wmem_max=67108864
    sysctl -q -w net.core.netdev_max_backlog=5000

    # dirty ratio (battery: lower; perf: moderate)
    case "$PROFILE" in
        battery)
            sysctl -q -w vm.dirty_ratio=15
            sysctl -q -w vm.dirty_background_ratio=5
            ;;
        performance)
            sysctl -q -w vm.dirty_ratio=20
            sysctl -q -w vm.dirty_background_ratio=10
            ;;
    esac
}

# ---------------------------------------------------------------------------
# cpufreq / scheduler
# ---------------------------------------------------------------------------
apply_cpu() {
    set_governor() { # cpu
        local g=/sys/devices/system/cpu/cpu$1/cpufreq/scaling_governor
        p "$g" schedutil
    }
    set_eas() { # cpu
        local e=/sys/devices/system/cpu/cpu$1/cpufreq/schedutil
        p "$e/rate_limit_us" 500
        p "$e/up_rate_limit_us" 500
        p "$e/down_rate_limit_us" 2000
    }

    cpu_each set_governor
    cpu_each set_eas

    # uclamp: max cap for foreground, min 0 for background
    p /proc/sys/kernel/sched_util_clamp_min 0
    p /proc/sys/kernel/sched_util_clamp_max 1024

    # schedtune boosts (1+3+4 topology)
    p /dev/stune/top-app/schedtune.boost 20
    p /dev/stune/top-app/schedtune.prefer_idle 1
    p /dev/stune/foreground/schedtune.boost 10
    p /dev/stune/foreground/schedtune.prefer_idle 1
    p /dev/stune/background/schedtune.boost 0
    p /dev/stune/background/schedtune.prefer_idle 1

    # max frequency per profile (prime = cpu7)
    case "$PROFILE" in
        performance)
            p /sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq 2918400000
            p /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 710400000
            ;;
        battery)
            p /sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq 2092800000
            p /sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq 1766400000
            ;;
        *)
            p /sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq 2496000000
            ;;
    esac
}

# ---------------------------------------------------------------------------
# I/O
# ---------------------------------------------------------------------------
apply_io() {
    for b in /sys/block/sda /sys/block/sdb /sys/block/dm-*; do
        [ -d "$b" ] || continue
        p "$b/queue/scheduler" maple
        p "$b/queue/iosched/slice_idle" 0
        p "$b/queue/iosched/low_latency" 1
        p "$b/queue/nr_requests" 256
        p "$b/queue/read_ahead_kb" 128
        p "$b/queue/wbt_lat_usec" 2000
    done
}

# ---------------------------------------------------------------------------
# zRAM
# ---------------------------------------------------------------------------
apply_zram() {
    local z=/sys/block/zram0
    [ -d "$z" ] || return 0
    p "$z/comp_algorithm" zstd
    p "$z/max_comp_streams" 8
    case "$PROFILE" in
        performance) p "$z/disksize" 2147483648 ;;  # 2GB
        battery)     p "$z/disksize" 4294967296 ;;  # 4GB
        *)           p "$z/disksize" 3221225472 ;;  # 3GB
    esac
    p "$z/writeback_limit_enable" 1
}

# ---------------------------------------------------------------------------
# Thermal (soft caps, do not fight the kernel thermal framework)
# ---------------------------------------------------------------------------
apply_thermal() {
    # power_allocator is the battery-friendly default already
    for tz in /sys/class/thermal/thermal_zone*; do
        [ -d "$tz" ] || continue
        p "$tz/mode" enabled
    done
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
apply_sysctl
apply_cpu
apply_io
apply_zram
apply_thermal

echo "[aurora] tuning applied (profile=$PROFILE)"
