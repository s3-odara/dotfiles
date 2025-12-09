scriptencoding utf-8

" プラグイン
let s:minpac_dir = expand('~/.vim/pack/minpac/opt/minpac')
if !isdirectory(s:minpac_dir)
  call system('git clone https://github.com/k-takata/minpac ' . s:minpac_dir)
  packadd minpac
endif

command! PackUpdate call PackInit() | call minpac#update()
command! PackClean  call PackInit() | call minpac#clean()
command! PackStatus packadd minpac | call minpac#status()

function! PackInit() abort
  packadd minpac
  call minpac#init()
  
  call minpac#add('https://github.com/k-takata/minpac.git', {'type': 'opt'})
  
  " UI, Tools
  call minpac#add('https://github.com/itchyny/lightline.vim.git')
  call minpac#add('https://github.com/itchyny/vim-gitbranch.git')
  call minpac#add('https://github.com/mhinz/vim-signify.git')
  call minpac#add('https://github.com/ctrlpvim/ctrlp.vim.git', {'type': 'opt'})
  
  " Filer
  call minpac#add('https://github.com/lambdalisue/vim-fern.git', {'type': 'opt'})
  call minpac#add('https://github.com/lambdalisue/vim-fern-git-status.git', {'type': 'opt'})
  
  " LSP, Completion
  call minpac#add('https://github.com/prabirshrestha/vim-lsp.git', {'type': 'opt'})
  call minpac#add('https://github.com/mattn/vim-lsp-settings.git', {'type': 'opt'})
  call minpac#add('https://github.com/prabirshrestha/asyncomplete.vim.git', {'type': 'opt'})
  call minpac#add('https://github.com/prabirshrestha/asyncomplete-lsp.vim.git', {'type': 'opt'})
  
  " Snippet, Lexiv
  call minpac#add('https://github.com/hrsh7th/vim-vsnip.git', {'type': 'opt'})
  call minpac#add('https://github.com/hrsh7th/vim-vsnip-integ.git', {'type': 'opt'})
  call minpac#add('https://github.com/mattn/vim-lexiv.git', {'type': 'opt'})
endfunction

" 設定
set encoding=utf-8
set fileencodings=utf-8,iso-2022-jp,euc-jp,sjis
set expandtab
set tabstop=4
set softtabstop=-1    " shiftwidthに従う
set shiftwidth=0      " tabstopに従う
set autoindent
set completeopt=menuone,noinsert,noselect,preview

set number
set ruler
set showcmd
set laststatus=2
set wildmenu
set hlsearch
set incsearch
set ignorecase
set smartcase

set mouse=a
set ttymouse=sgr      " alacritty/tmux用
set updatetime=500    " signifyの更新速度向上
set timeoutlen=1500
set ttimeoutlen=50
set noesckeys

" 色
set termguicolors
set background=dark
set diffopt=internal,filler,algorithm:patience,indent-heuristic

" スペルチェック
set spelllang=en_us,cjk
set dictionary=~/.vim/dict/words
set thesaurus=~/.vim/dict/thesaurus

syntax on
filetype plugin indent on

" キーマップ
let mapleader = "\<Space>"
xnoremap <silent> "+y :<C-u>call Osc52Copy()<CR>
nnoremap "+p :let @"=substitute(system("wl-paste --no-newline"), '<C-v><C-m>', '', 'g')<cr>p
nnoremap "*p :let @"=substitute(system("wl-paste --no-newline --primary"), '<C-v><C-m>', '', 'g')<cr>p
nnoremap <F3> <Cmd>nohlsearch<CR>
inoremap <C-x><C-d> <C-x><C-k>

nnoremap <leader>d <cmd>LspDefinition<CR>
nnoremap <leader>e <cmd>LspDeclaration<CR>
nnoremap <leader>r <cmd>LspReferences<CR>
nnoremap <leader>h  <cmd>LspHover<CR>
nnoremap <leader>rn <cmd>LspRename<CR>
nnoremap <leader>a <cmd>LspCodeAction<CR>
nnoremap <leader>f  <cmd>LspDocumentFormat<CR>
nnoremap <leader>[ <cmd>LspPreviousError<CR>
nnoremap <leader>] <cmd>LspNextError<CR>

" プラグインロード
" Insert Mode
augroup LazyLoadInsert
    autocmd!
    autocmd InsertEnter * ++once packadd vim-vsnip | packadd vim-vsnip-integ | packadd vim-lexiv
augroup END

" LSP
let s:lsp_filetypes = ['python', 'toml', 'rust', 'c', 'cpp', 'vim', 'sh', 'yaml', 'html', 'css', 'lua']

augroup LazyLoadLsp
  autocmd!
  execute 'autocmd FileType ' . join(s:lsp_filetypes, ',') . ' call s:load_lsp()'
augroup END

function! s:load_lsp() abort
  if exists('g:lsp_loaded')
    return
  endif

  packadd vim-lsp
  packadd asyncomplete.vim
  packadd asyncomplete-lsp.vim
  packadd vim-lsp-settings

  if &filetype != ''
    execute 'doautocmd FileType ' . &filetype
  endif
endfunction

" プラグイン設定

" asyncomplete.vim
inoremap <expr> <Tab>
      \ pumvisible() ? "\<C-n>" :
      \ vsnip#available(1) ? "\<Plug>(vsnip-expand-or-jump)" :
      \ "\<Tab>"
inoremap <expr> <S-Tab>
      \ pumvisible() ? "\<C-p>" :
      \ vsnip#jumpable(-1) ? "\<Plug>(vsnip-jump-prev)" :
      \ "\<S-Tab>"
let g:asyncomplete_popup_delay = 200

" vim-lsp
let g:lsp_settings = { 'typos-lsp': {'disabled': v:false} }
let g:lsp_diagnostics_echo_cursor = 1
let g:lsp_diagnostics_echo_delay = 100
let g:lsp_diagnostics_highlights_delay = 100
let g:lsp_diagnostics_signs_delay = 100
let g:lsp_diagnostics_virtual_text_delay = 100
let g:lsp_document_code_action_signs_delay = 200
let g:lsp_document_highlight_delay = 100
let g:lsp_diagnostics_virtual_text_prefix = "🍖 "

" lightline.vim
let g:lightline = {
      \ 'active': {
      \   'left': [ ['mode', 'paste'], ['gitbranch', 'readonly', 'absolutepath', 'modified'] ]
      \ },
      \ 'component_function':{ 'gitbranch': 'Gitbranch' },
      \ 'separator': { 'left': "\ue0b0", 'right': "\ue0b2" },
      \ }

function! Gitbranch()
    let head = gitbranch#name()
    if head != ""
        let head = "\uf126 " .. head
    endif
    return head
endfunction

" ctrlp
nnoremap <leader>p <cmd>packadd ctrlp.vim \| call ctrlp#init(0)<CR>

" fern
nnoremap <leader>t <cmd>packadd vim-fern \| packadd vim-fern-git-status \| Fern . -reveal=% -drawer -toggle -width=30<CR> 
let g:fern#default_hidden = 1
let g:netrw_liststyle = 1

augroup fern-custom
  autocmd! *
  autocmd FileType fern call s:init_fern()
augroup END

function! s:init_fern() abort
  nmap <buffer><expr>
      \ <Plug>(fern-my-expand-or-collapse)
      \ fern#smart#leaf(
      \   "\<Plug>(fern-action-collapse)",
      \   "\<Plug>(fern-action-expand)",
      \   "\<Plug>(fern-action-collapse)"
      \ )

  nmap <buffer><expr>
      \ <Plug>(fern-my-open-or-expand)
      \ fern#smart#leaf(
      \   "\<Plug>(fern-action-open)",
      \   "\<Plug>(fern-action-expand)"
      \ )
  
  nmap <buffer><expr>
      \ <Plug>(fern-my-open-or-expand-or-collapse)
      \ fern#smart#leaf(
      \   "\<Plug>(fern-action-open)",
      \   "\<Plug>(fern-action-expand)",
      \   "\<Plug>(fern-action-collapse)"
      \ )

  nmap <buffer><nowait> <CR> <Plug>(fern-my-expand-or-collapse)
  nmap <buffer> <LeftRelease> <Plug>(fern-my-open-or-expand-or-collapse)
endfunction

" --- ColorScheme (Habamax) ---
function! DefineMyHighlights()
    if g:colors_name is "habamax"
        highlight Normal ctermbg=NONE guibg=NONE
        highlight NonText ctermbg=NONE guibg=NONE
        highlight SpecialKey ctermbg=NONE guibg=NONE
        highlight EndOfBuffer ctermbg=NONE guibg=NONE
    endif
endfunction

augroup TransparentBG
    autocmd!
    autocmd ColorScheme * call DefineMyHighlights()
augroup END

colorscheme habamax

" 自動化・ユーティリティ

" IME Control (fcitx5)
augroup fcitx5_control_fn
  autocmd!
  function! s:FcitxOnInsertLeave()
    let w:im_name = trim(system('fcitx5-remote -n'))
    if has('job')
      call job_start(['fcitx5-remote', '-o'])
    else
      call system('fcitx5-remote -o')
    endif
  endfunction

  function! s:FcitxOnInsertEnter()
    if exists('w:im_name') && w:im_name != 'keyboard-us'
      if has('job')
        call job_start(['fcitx5-remote', '-c'])
      else
        call system('fcitx5-remote -c')
      endif
    endif
  endfunction

  autocmd InsertLeave * call s:FcitxOnInsertLeave()
  autocmd InsertEnter * call s:FcitxOnInsertEnter()
augroup END

" 特定ファイルタイプ
augroup noindent
  autocmd!
  " autocmd FileType html,htmldjango setlocal indentexpr= tabstop=2
augroup END

" ディレクトリ自動作成
" https://vim-jp.org/vim-users-jp/2011/02/20/Hack-202.html
augroup vimrc-auto-mkdir
  autocmd!
  autocmd BufWritePre * call s:auto_mkdir(expand('<afile>:p:h'), v:cmdbang)
  function! s:auto_mkdir(dir, force)
    if !isdirectory(a:dir) && (a:force ||
    \   input(printf('"%s" does not exist. Create? [y/N]', a:dir)) =~? '^y\%[es]$')
      call mkdir(iconv(a:dir, &encoding, &termencoding), 'p')
    endif
  endfunction
augroup END

" 開いているファイルにカレントディレクトリを移動
autocmd BufEnter * let s:root = finddir('.git', expand('%:p:h') . ';') |
      \ if !empty(s:root) |
      \   execute 'cd ' . fnameescape(fnamemodify(s:root, ':h')) |
      \ endif

" Syntaxハイライトを利用したオムニ補完
" https://vim-jp.org/vim-users-jp/2009/11/01/Hack-96.html
" https://vim-jp.org/vimdoc-ja/insert.html#ft-syntax-omni
augroup omni
    autocmd!
    autocmd FileType *
    \   if &l:omnifunc == ''
    \ |   setlocal omnifunc=syntaxcomplete#Complete
    \ | endif
augroup END

" GPG暗号化ファイルの透過編集
" By Wouter Hanegraaff <wouter@blub.net>
augroup encrypted
  au!
  autocmd BufReadPre,FileReadPre *.gpg set viminfo=
  autocmd BufReadPre,FileReadPre *.gpg set noswapfile
  autocmd BufReadPre,FileReadPre *.gpg set noundofile
  autocmd BufReadPre,FileReadPre *.gpg set bin
  autocmd BufReadPre,FileReadPre *.gpg let ch_save = &ch|set ch=2
  autocmd BufReadPost,FileReadPost *.gpg '[,']!gpg --decrypt 2> /dev/null
  autocmd BufReadPost,FileReadPost *.gpg set nobin
  autocmd BufReadPost,FileReadPost *.gpg let &ch = ch_save|unlet ch_save
  autocmd BufReadPost,FileReadPost *.gpg execute ":doautocmd BufReadPost " . expand("%:r")
  autocmd BufWritePre,FileWritePre *.gpg '[,']!gpg --default-recipient-self -ae 2>/dev/null
  autocmd BufWritePost,FileWritePost *.gpg u
augroup END

" OSC52を利用したコピー
function! Osc52Copy()
  " 現在の無名レジスタの中身を退避
  let l:save_reg = @"
  normal! gvy
  let l:content = @"
  " レジスタを復元
  let @" = l:save_reg
  if len(l:content) == 0
    echo "Nothing to copy"
    return
  endif
  " Base64
  let l:b64 = system('base64 | tr -d "\n"', l:content)
  " 文字数制限
  if len(l:b64) > 100000
    redraw
    echohl WarningMsg
    echo "Warning: Content too large for OSC 52 copy."
    echohl None
    return
  endif
  " シーケンスを作成
  "    \x1b]52;c;{base64}\x07
  let l:seq = "\x1b]52;c;" . l:b64 . "\x07"
  call writefile([l:seq], "/dev/tty", "b")
  redraw!
  echo "Copied to clipboard (OSC 52)"
endfunction

