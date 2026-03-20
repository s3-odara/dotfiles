# river 0.4 + rill 移行メモ

## この移行で維持したもの

- compositor としての `river` 起動
- `dbus-run-session -- river` と `XDG_CURRENT_DESKTOP=river`
- `waybar`, `fnott`, `swaybg`, `swayidle`, `fcitx5`, `wlr-randr`, `wob`
- `Super+Q`, `Super+Shift+Return`, `Super+S`, `Super+M`, `Super+F`
- `Super+1..9`, `Super+Shift+1..9`, ``Super+` ``
- `Super+Arrow` と `Super+Comma/Period` による output focus
- 音量、マイク、輝度、スクリーンショット、`playerctl`

## 今回切り捨てたもの

- `rivertile` と `send-layout-cmd`
- tags ベース運用全般
- `Super+0` / `Super+Shift+0` による all tags
- `toggle-float`, `map-pointer`, `map-switch`, `declare-mode`, `passthrough`
- 任意 move / resize / snap
- `rule-add` による float / csd ルール
- tags 以外の `riverctl` WM 設定

## 代替または再配置

- `Super+H/L` は `rill` の左右フォーカスへ割当
- `Super+Shift+H/L` は `rill` の左右移動へ割当
- `Super+P` は範囲選択してクリップボードへコピー
- `Super+Shift+P` は範囲選択して保存
- `Super+R` は従来どおり `lock-and-suspend`
- `Super+Shift+R` は `rill` 設定再読込

## 起動責務

- `~/.config/river/init` は共通セッション初期化と WM ランチャ呼出しだけに絞ります
- `~/.local/bin/wayland-session-init` が入力、通知、バー、idle など WM 非依存な初期化を担当します
- 壁紙は `~/.config/river/init` から `wm-launch` の後段で起動します
- `~/.local/bin/wm-launch` が初回の WM プロセス起動を担当します
- `~/.local/bin/wm-switch <wm>` が新しい WM を起動してから現在の WM に終了を促します
- WM 固有設定は各 WM の設定ファイルに書きます

## 現時点で未移行のもの

- `XF86Display` による HDMI 切替
  - `rill` のキー対応に含まれていないため未移行です
- `Print` 単体スクリーンショット
  - `rill` のキー対応に含まれていないため `Super+Shift+P` へ寄せています
- `XF86AudioPlay` / `XF86AudioPause`
  - `rill` のキー対応に含まれていないため未移行です

## 今回追加した補助クライアント

- `~/.local/bin/river-inputctl`
  - `river_input_management_v1` と `river_libinput_config_v1` を使って repeat と libinput 設定を適用します
  - 既定で常駐し、あとから接続された入力デバイスにも同じルールを適用します
  - `~/.local/src/river-inputctl/Makefile` でビルドし、dotfiles の `stow` / `restow` 時に更新します

## 汎用補助スクリプト

- `~/.local/bin/brightness-wob`
- `~/.local/bin/screenshot-copy`
- `~/.local/bin/screenshot-save`
- `~/.local/bin/session-idle`
- 旧 `rill-*` 名は削除し、WM 固有名の補助スクリプトは持たない方針にします

## Waybar

- `river/tags` は削除済みです
- workspace 表示はこのまま入れずに運用します
