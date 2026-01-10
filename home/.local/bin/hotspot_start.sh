#!/bin/bash
set -eu

PHY_IF="wlan0"  # iwd が使っている物理 Wi-Fi デバイス
AP_IF="ap0"     # これから作成する AP 用仮想デバイス
AP_IP="192.168.10.1"
AP_SUBNET_CIDR="24"

# firewalld ゾーン
FWD_ZONE="trusted"  # APインターフェース用 (信頼ゾーン)
DEFAULT_INET_ZONE="public" # wlan0 が 'no zone' だった場合に使うゾーン

# 一時ファイル
VARS_FILE="/run/hotspot_vars"

# インターネット接続中のインターフェースを自動検出
INET_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
if [ -z "$INET_IF" ]; then
    echo "エラー: インターネット接続が見つかりません。" >&2
    exit 1
fi
echo "インターネット共有元: $INET_IF"

firewall-cmd --zone=external --add-interface=wlan0
INET_IF_ADDED_BY_SCRIPT="true" # 停止時に削除するためフラグを立てる
echo "インターネット側ゾーンを externalに設定します"


# 1. 仮想 AP インターフェースを作成
iw dev wlan0 interface add ap0 type __ap

# 2. AP インターフェースに静的 IP を割り当て
ip addr add "${AP_IP}/${AP_SUBNET_CIDR}" dev ap0
ip link set dev ap0 up

# 3. IP フォワーディングを有効化
sysctl -w net.ipv4.ip_forward=1

# 4. firewalld の設定 (ランタイムのみ)
# AP側IFを $FWD_ZONE (trusted) に割り当て
firewall-cmd --zone="$FWD_ZONE" --add-interface="$AP_IF"

# $INET_ZONE (検出またはデフォルト) でマスカレード(NAT)を有効化
firewall-cmd --zone=external --add-masquerade

NEW_PASS=$(tr -dc 'a-z0-9' < /dev/urandom | fold -w 50 | head -1)
sed -i.bak "s/^wpa_passphrase=.*$/wpa_passphrase=$NEW_PASS/" "/etc/hostapd/hostapd.conf"

if [ $? -ne 0 ]; then
        echo "エラー: password の更新に失敗しました。" >&2
            exit 1
fi

systemctl start dnsmasq
systemctl start hostapd

echo "--- 接続用QRコード  ---"
qrencode -t UTF8 "WIFI:S:ThinkPad_8840hs;T:WPA;P:${NEW_PASS};;"
echo "-------------------------------------"

# 5. 停止スクリプト用に変数を保存
echo "INET_IF=$INET_IF" > "$VARS_FILE"
echo "AP_IF=$AP_IF" >> "$VARS_FILE"
echo "FWD_ZONE=$FWD_ZONE" >> "$VARS_FILE"
echo "INET_ZONE=external" >> "$VARS_FILE"
echo "INET_IF_ADDED_BY_SCRIPT=$INET_IF_ADDED_BY_SCRIPT" >> "$VARS_FILE"

echo "firewalld ランタイム設定完了"
