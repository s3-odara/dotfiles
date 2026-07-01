#!/usr/bin/env zsh

emulate -L zsh
setopt err_exit pipe_fail no_unset

# popup内のtmuxセッションで同じキーを押した場合は、popupを閉じる
current_session="$(tmux display-message -p '#S')"

if [[ "$current_session" == popup_agent_* ]]; then
  tmux detach-client
  exit 0
fi

# 現在のtmux paneのディレクトリ
pane_path="$(tmux display-message -p -F '#{pane_current_path}')"
dir_name="${pane_path:t}"

# セッション名に使いやすいようにディレクトリ名をsanitize
safe_dir="${dir_name//[^A-Za-z0-9_-]/_}"

# フルパスのhash値を付ける
if command -v b2sum >/dev/null 2>&1; then
  path_hash="$(printf '%s' "$pane_path" | b2sum | awk '{print $1}')"
elif command -v cksum >/dev/null 2>&1; then
  path_hash="$(printf '%s' "$pane_path" | cksum | awk '{print $1}')"
fi

short_hash="${path_hash[1,8]}"
popup_session="popup_agent_${safe_dir}_${short_hash}"

# popupサイズ
width="90%"
height="90%"

# セッションがなければ作る
if ! tmux has-session -t "$popup_session" 2>/dev/null; then
  tmux new-session -d -s "$popup_session" -c "$pane_path"
  tmux send-keys -t "$popup_session" "opencode" C-m
fi



# 既存または新規のtmuxセッションをpopupで開く
tmux display-popup \
  -d "$pane_path" \
  -xC \
  -yC \
  -w "$width" \
  -h "$height" \
  -s "bg=terminal,fg=terminal" \
  -S "bg=terminal,fg=terminal" \
  -E "tmux attach-session -t $popup_session"
