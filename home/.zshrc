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

# vcs_info for Git status in prompt
autoload -Uz vcs_info
setopt PROMPT_SUBST

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats       ' on %F{yellow}%b%f%c%u'
zstyle ':vcs_info:git:*' actionformats ' on %F{yellow}%b%f (%F{magenta}%a%f)'
zstyle ':vcs_info:git:*' stagedstr     ' %F{green}●%f'
zstyle ':vcs_info:git:*' unstagedstr   ' %F{red}●%f'

add-zsh-hook precmd vcs_info

PROMPT='%F{green}%n%f@%F{blue}%m%f:%~${vcs_info_msg_0_}
%# '

# Plugins (guard with -r)
if [[ -r /usr/share/zsh/site-functions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh/site-functions/zsh-autosuggestions.zsh
fi

# zsh-syntax-highlighting should be sourced last
if [[ -r /usr/share/zsh/site-functions/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/site-functions/zsh-syntax-highlighting.zsh
fi

