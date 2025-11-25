# Created by newuser for 5.9
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

autoload -Uz compinit
compinit

autoload -Uz promptinit
promptinit

export PURE_CMD_MAX_EXEC_TIME=1
export PURE_PROMPT_SYMBOL="%%"
prompt pure

GPG_TTY=$(tty)
export GPG_TTY
KEYTIMEOUT=5

#gcryptレポでgit pullを無効にする
typeset -g MY_SLOW_REPO_PATH="/home/odara/git/memo"

_toggle_pure_git_display() {
  if [[ "$PWD" == "$MY_SLOW_REPO_PATH"* ]]; then
      export PURE_GIT_PULL=0 

  else
      export PURE_GIT_PULL=0
  fi
}

# precmd フックに関数を追加
autoload -Uz add-zsh-hook
add-zsh-hook precmd _toggle_pure_git_display


set -a; source <(envsubst < ~/.env); set +a

RPROMPT+='%F{#8798e8}%T'

zstyle ':prompt:pure:user' color '#04b5b5'
zstyle ':prompt:pure:host' color '#dd8364'
zstyle ':prompt:pure:git:branch' color '#a5a645'
zstyle ':prompt:pure:prompt:*' color '#33add6'
zstyle ':prompt:pure:path' color '#5db47b'
zstyle ':prompt:pure:execution_time' color '#a5a645'
zstyle ':prompt:pure:git:dirty' color '#da7fa2'
zstyle ':prompt:pure:git:action' color '#d87fa2'
zstyle ':prompt:pure:git:arrow' color '#33add6'

zstyle :prompt:pure:git:stash show yes

source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
