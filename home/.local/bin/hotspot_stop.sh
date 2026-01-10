#!/bin/bash
set -eu

VARS_FILE="/run/hotspot_vars"

# デフォルト値
AP_IF="ap0"
INET_IF=""
FWD_ZONE="trusted"
INET_ZONE="external"
INET_IF_ADDED_BY_SCRIPT="false" # デフォルトは false

if [ -f "$VARS_FILE" ]; then
    source "$VARS_FILE"
else
    echo "変数ファイル ($VARS_FILE) が見つかりません。フォールバック値を使用します。" >&2
fi

# 1. IP フォワーディングを無効化
sysctl -w net.ipv4.ip_forward=0

# 2. firewalld のランタイム設定を削除
    # 保存された $INET_ZONE からマスカレードを削除
firewall-cmd --zone="$INET_ZONE" --remove-masquerade

firewall-cmd --zone="$INET_ZONE" --remove-interface=wlan0
firewall-cmd --zone="$FWD_ZONE" --remove-interface="$AP_IF"

# 3. 仮想 AP インターフェースを削除
if ip link show "$AP_IF" > /dev/null 2>&1; then
    iw dev "$AP_IF" del
fi

# 4. 一時ファイルを削除
rm -f "$VARS_FILE"
systemctl stop hostapd
systemctl stop dnsmasq

echo "ホットスポットクリーンアップ完了"
