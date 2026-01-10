# Created by newuser for 5.9
source /usr/share/zsh/site-functions/zsh-autosuggestions.zsh

fpath+=("/usr/share/zsh/site-functions")

autoload -Uz compinit
compinit

autoload -Uz promptinit
promptinit; prompt gentoo

GPG_TTY=$(tty)
export GPG_TTY

alias ssh="gpg-connect-agent updatestartuptty /bye >/dev/null && ssh"
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
gpgconf --launch gpg-agent

KEYTIMEOUT=5

# --- vcs_info (Gitステータス表示) の設定 ---
 
# 1. vcs_infoモジュールの読み込みと、プロンプト内での変数展開を許可
autoload -Uz vcs_info
setopt PROMPT_SUBST
 
# 2. プロンプトが表示される直前に vcs_info を実行する設定
precmd() {
  vcs_info
}
 
# 3. vcs_info が Git を認識するように有効化
zstyle ':vcs_info:*' enable git
 
# 4. 表示フォーマットを指定
# ${vcs_info_msg_0_} という変数に結果が格納される
 
# 通常時のフォーマット: ' on (ブランチ名)(Staged変更)(Unstaged変更)'
# %b: ブランチ名 (黄色)
# %c: Staged変更 (zstyle stagedstr で指定した記号)
# %u: Unstaged変更 (zstyle unstagedstr で指定した記号)
zstyle ':vcs_info:git:*' formats       ' on %F{yellow}%b%f%c%u'
 
# マージ中などのアクションがある場合のフォーマット (例: ' on main (MERGING)')
# %a: アクション名 (マゼンタ色)
zstyle ':vcs_info:git:*' actionformats ' on %F{yellow}%b%f (%F{magenta}%a%f)'
 
# Staged 変更がある場合に %c の部分に表示する記号
zstyle ':vcs_info:git:*' stagedstr   ' %F{green}●%f'  # (緑丸)
 
# Unstaged 変更がある場合に %u の部分に表示する記号
zstyle ':vcs_info:git:*' unstagedstr ' %F{red}●%f'    # (赤丸)
 
# --- ここまで vcs_info の設定 ---
 
 
# 5. 最終的なプロンプトの設定
# 以前のプロンプト設定に ${vcs_info_msg_0_} を追加
# (Gitリポジトリ以外では ${vcs_info_msg_0_} は空になります)
PROMPT='%F{green}%n%f@%F{blue}%m%f:%~${vcs_info_msg_0_}
%# '



source /usr/share/zsh/site-functions/zsh-syntax-highlighting.zsh
