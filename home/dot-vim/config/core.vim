vim9script

g:mapleader = "\<Space>"

# Core options
set encoding=utf-8
set fileencodings=utf-8,iso-2022-jp,euc-jp,sjis

set expandtab
set tabstop=8         # hardtabがある文書では8から変えないほうが良いらしい？
set softtabstop=-1    # shiftwidthに従う
set shiftwidth=4      # 0にするとtabstopに従う
set autoindent

set number
set ruler
set showcmd
set laststatus=2
set hlsearch
set incsearch
set ignorecase
set smartcase
set signcolumn=yes
set hidden

set mouse=a
set ttymouse=sgr      # alacritty/tmux用
set updatetime=4000   # gitsignを非同期にした
set timeoutlen=1500   # キーマップを押しやすくする
set ttimeoutlen=50    # エスケープシーケンスの待ち時間
set iminsert=2
set imsearch=-1
set undofile
set nobackup

# UI / colors
set diffopt=internal,filler,algorithm:patience,indent-heuristic,closeoff,inline:char,linematch:60

if filereadable('/usr/share/dict/words')
  set dictionary=/usr/share/dict/words
elseif filereadable(expand('~/.vim/dict/words'))
  set dictionary=~/.vim/dict/words
endif
set thesaurus=~/.vim/dict/thesaurus.txt

syntax on
filetype plugin indent on
