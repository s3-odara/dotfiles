#!/bin/sh

# ACアダプターのオンライン状態を示すファイルのパス。環境によって 'AC' や 'ADP1' など名前が異なります。
# /sys/class/power_supply/ を確認して、ご自身の環境に合わせてください。
AC_ADAPTER_PATH="/sys/class/power_supply/AC/online"

# ファイルが存在し、かつ内容が '0' (オフライン) の場合
if [ -f "$AC_ADAPTER_PATH" ] && [ "$(cat "$AC_ADAPTER_PATH")" = "0" ]; then
    # 以前作成した、タイマーを停止して閾値をリセットするサービスを開始する
    systemctl start reset-charge-threshold.service
fi
