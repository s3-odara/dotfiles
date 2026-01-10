#!/bin/bash

POWER_SUPPLY_PATH="/sys/class/power_supply/AC/online"

# AC接続時の設定
GOVERNOR_AC="performance"
EPP_AC="performance" # Energy Performance Preference

# バッテリー駆動時の設定
GOVERNOR_BAT="powersave"
EPP_BAT="power"

GOVERNOR_TO_SET=""
EPP_TO_SET=""

if [ -f "$POWER_SUPPLY_PATH" ] && [ "$(cat "$POWER_SUPPLY_PATH")" -eq 1 ]; then
    GOVERNOR_TO_SET=$GOVERNOR_AC
    EPP_TO_SET=$EPP_AC
else
    GOVERNOR_TO_SET=$GOVERNOR_BAT
    EPP_TO_SET=$EPP_BAT
fi

for gov_path in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [ -f "$gov_path" ]; then
        echo "$GOVERNOR_TO_SET" > "$gov_path"
    fi
done

for epp_path in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    if [ -f "$epp_path" ]; then
        echo "$EPP_TO_SET" > "$epp_path"
    fi
done


