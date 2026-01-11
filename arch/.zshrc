# ~/.zshrc
# Interactive shell configuration.

[[ -o interactive ]] || return

# Completion
fpath=(
  /usr/share/zsh/site-functions
  $fpath
)

autoload -Uz compinit
# Use XDG cache for compdump
_compdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p -- "${_compdump:h}" 2>/dev/null
compinit -d "${_compdump}"

# Key timeout (zsh: hundredths of a second)
KEYTIMEOUT=5

# setopt
setopt interactivecomments

# History (XDG)
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
mkdir -p -- "${HISTFILE:h}" 2>/dev/null
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY

# Hooks
autoload -Uz add-zsh-hook

# Keep GPG_TTY fresh and inform gpg-agent (safe for interactive)
_gpg_update_tty() {
  export GPG_TTY="${TTY:-$(tty 2>/dev/null)}"
  command -v gpg-connect-agent >/dev/null 2>&1 || return 0
  gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
}
add-zsh-hook precmd _gpg_update_tty

# ---- Prompt (Pure) : imported from zshrc2 ----
autoload -Uz promptinit
promptinit

# (optional) allow prompt command substitution etc.
setopt PROMPT_SUBST

export PURE_CMD_MAX_EXEC_TIME=1
export PURE_PROMPT_SYMBOL="%%"

# gcryptレポでgit pullを無効にする（Pure 用）
typeset -g MY_SLOW_REPO_PATH="/home/odara/git/memo"

_toggle_pure_git_display() {
  if [[ "$PWD" == "$MY_SLOW_REPO_PATH"* ]]; then
    export PURE_GIT_PULL=0
  else
    export PURE_GIT_PULL=0
  fi
}
add-zsh-hook precmd _toggle_pure_git_display

# Pure theme colors / options
zstyle ':prompt:pure:user' color '#04b5b5'
zstyle ':prompt:pure:host' color '#dd8364'
zstyle ':prompt:pure:git:branch' color '#a5a645'
zstyle ':prompt:pure:prompt:*' color '#33add6'
zstyle ':prompt:pure:path' color '#5db47b'
zstyle ':prompt:pure:execution_time' color '#a5a645'
zstyle ':prompt:pure:git:dirty' color '#da7fa2'
zstyle ':prompt:pure:git:action' color '#d87fa2'
zstyle ':prompt:pure:git:arrow' color '#33add6'
zstyle ':prompt:pure:git:stash' show yes

# Activate Pure prompt
prompt pure

# Right prompt: clock
RPROMPT+='%F{#8798e8}%T'
# ---- Prompt (Pure) end ----

# Plugins (guard with -r)
if [[ -r /usr/share/zsh/site-functions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh/site-functions/zsh-autosuggestions.zsh
fi

# zsh-syntax-highlighting should be sourced last
if [[ -r /usr/share/zsh/site-functions/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/site-functions/zsh-syntax-highlighting.zsh
fi

