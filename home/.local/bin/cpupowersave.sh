#!/bin/bash

# スケーリングガバナー設定
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo powersave > "$cpu"
done

# EPP 設定
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    echo power > "$cpu"
done

