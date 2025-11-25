scriptencoding utf-8

" 使用プラグイン
" lightline.vim
" vim-gitbranch
" fern
" fern-gitstatus
" vim-lsp
" vim-lsp-settings
" asyncomplete.vim
" asyncomplete-lsp.vim
" vim-vsnip
" vim-vsnip-integ
" ctrlp
" vim-signify
" vim-lexiv

" waylandでクリップボードを使う
xnoremap "+y y:call system("wl-copy", @")<cr>
nnoremap "+p :let @"=substitute(system("wl-paste --no-newline"), '<C-v><C-m>', '', 'g')<cr>p
nnoremap "*p :let @"=substitute(system("wl-paste --no-newline --primary"), '<C-v><C-m>', '', 'g')<cr>p

" escでimeをオフにする
augroup fcitx5_control_fn
  autocmd!

  function! s:FcitxOnInsertLeave()
    let w:im_name = trim(system('fcitx5-remote -n'))
    silent !fcitx5-remote -o
  endfunction

  function! s:FcitxOnInsertEnter()
    if exists('w:im_name') && w:im_name != 'keyboard-us'
      silent !fcitx5-remote -c
    endif
  endfunction

  autocmd InsertLeave * call <SID>FcitxOnInsertLeave()
  autocmd InsertEnter * call <SID>FcitxOnInsertEnter()

augroup END

" asyncomplete.vim
inoremap <expr> <Tab>   pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <cr>    pumvisible() ? asyncomplete#close_popup() : "\<cr>"

" ctrlp
nnoremap <silent> <space>f <Cmd>CtrlP<CR>
let g:ctrlp_map = ''

" fern
augroup fern-custom
  autocmd! *
  autocmd FileType fern call s:init_fern()
augroup END

nnoremap <space>t <cmd>Fern . -reveal=% -drawer -toggle -width=30<CR>

function! s:init_fern() abort
  nmap <buffer><expr>
      \ <Plug>(fern-my-expand-or-collapse)
      \ fern#smart#leaf(
      \   "\<Plug>(fern-action-collapse)",
      \   "\<Plug>(fern-action-expand)",
      \   "\<Plug>(fern-action-collapse)",
      \ )
  nmap <buffer><expr>
      \ <Plug>(fern-my-open-or-expand)
	    \ fern#smart#leaf(
	    \   "<Plug>(fern-action-open)",
	    \   "<Plug>(fern-action-expand)",
	    \ )
  nmap <buffer><expr>
      \ <Plug>(fern-my-open-or-expand-or-collapse)
      \ fern#smart#leaf(
      \ "<Plug>(fern-action-open)",
      \ "<Plug>(fern-action-expand)",
      \ "<Plug>(fern-action-collapse)",
      \)

  nmap <buffer><nowait> <CR> <Plug>(fern-my-expand-or-collapse)
  "  nmap <buffer> <LeftRelease> <Plug>(fern-action-edit)
  nmap <buffer> <LeftRelease> <Plug>(fern-my-open-or-expand-or-collapse)
endfunction

let g:fern#default_hidden = 1


let g:netrw_liststyle=1

"キー割り当て

nnoremap <F3> <Cmd>nohlsearch<CR>
inoremap <C-x><C-d> <C-x><C-k>

syntax on
filetype plugin indent on

augroup noindent
autocmd!
"autocmd FileType html,htmldjango setlocal indentexpr= tabstop=2
augroup END

" tab
set expandtab
set tabstop=4
set softtabstop=-1 "shiftwidthに従う
set shiftwidth=0 "tabstopに従う

set ttymouse=sgr " alacritty用。 xterm2でもtmuxとの相互運用性が良いけどsgrはさらに拡張されているぽい？
set wildmenu
set ruler
set mouse=a
set number
set hlsearch
set ignorecase
set incsearch
set smartcase
set laststatus=2
set autoindent
set background=dark
set showcmd
set updatetime=500 " signifyの更新速度向上
set termguicolors
set diffopt=internal,filler,algorithm:patience,indent-heuristic
set spelllang=en_us,cjk
set dictionary=~/.vim/dict/words
set thesaurus=~/.vim/dict/thesaurus
set timeoutlen=1500
set encoding=utf-8
set fileencodings=utf-8,iso-2022-jp,euc-jp,sjis
set noesckeys
set ttimeoutlen=50


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
    autocmd ColorScheme * :call DefineMyHighlights()
augroup END

colorscheme habamax

" lightline.vim
let g:lightline = {
      \ 'active': {
      \   'left': [ ['mode', 'paste'], ['gitbranch', 'readonly', 'absolutepath', 'modified'] ]
      \ },
      \ 'component_function':{ 'gitbranch': 'Gitbranch' },
      \ 'separator': { 'left': "\ue0b0", 'right': "\ue0b2" },
      \ 
      \}

" gitbranchにnerdフォントを使用
function! Gitbranch()
	let head = gitbranch#name()
	if head != ""
		let head = "\uf126 " .. head
	endif
	return head
endfunction

let g:lsp_diagnostics_echo_cursor = 1
let g:lsp_diagnostics_echo_delay = 100
let g:lsp_diagnostics_highlights_delay = 100
let g:lsp_diagnostics_signs_delay = 100
let g:lsp_diagnostics_virtual_text_delay = 100
let g:lsp_document_code_action_signs_delay =100
let g:lsp_document_highlight_delay = 100 " カーソル位置の単語が明るくなるやつ
let g:lsp_document_code_action_signs_delay = 200
let g:lsp_diagnostics_virtual_text_prefix = "🍖 "
let g:asyncomplete_popup_delay = 200

" ディレクトリ自動作成
" https://vim-jp.org/vim-users-jp/2011/02/20/Hack-202.html
augroup vimrc-auto-mkdir  " {{{
  autocmd!
  autocmd BufWritePre * call s:auto_mkdir(expand('<afile>:p:h'), v:cmdbang)
  function! s:auto_mkdir(dir, force)  " {{{
    if !isdirectory(a:dir) && (a:force ||
    \    input(printf('"%s" does not exist. Create? [y/N]', a:dir)) =~? '^y\%[es]$')
      call mkdir(iconv(a:dir, &encoding, &termencoding), 'p')
    endif
  endfunction  " }}}
augroup END  " }}}

" 開いているファイルにカレントディレクトリを移動
" https://vim-jp.org/vim-users-jp/2009/09/08/Hack-69.html
command! -nargs=? -complete=dir -bang CD  call s:ChangeCurrentDir('<args>', '<bang>')
function! s:ChangeCurrentDir(directory, bang)
    if a:directory == ''
        lcd %:p:h
    else
        execute 'lcd' . a:directory
    endif

    if a:bang == ''
        pwd
    endif
endfunction

" Change current directory.
nnoremap <silent> <Space>cd <Cmd>CD<CR>

" syntaxハイライトを利用したオムニ補完
" https://vim-jp.org/vim-users-jp/2009/11/01/Hack-96.html
" https://vim-jp.org/vimdoc-ja/insert.html#ft-syntax-omni
augroup omni
    autocmd!
autocmd FileType *
\   if &l:omnifunc == ''
\ |   setlocal omnifunc=syntaxcomplete#Complete
\ | endif
augroup END


" Transparent editing of gpg encrypted files.
" By Wouter Hanegraaff <wouter@blub.net>
augroup encrypted
au!
" First make sure nothing is written to ~/.viminfo while editing
" an encrypted file.
autocmd BufReadPre,FileReadPre *.gpg set viminfo=
" We don't want a swap file, as it writes unencrypted data to disk
autocmd BufReadPre,FileReadPre *.gpg set noswapfile
autocmd BufReadPre,FileReadPre *.gpg set noundofile
" Switch to binary mode to read the encrypted file
autocmd BufReadPre,FileReadPre *.gpg set bin
autocmd BufReadPre,FileReadPre *.gpg let ch_save = &ch|set ch=2
autocmd BufReadPost,FileReadPost *.gpg '[,']!gpg --decrypt 2> /dev/null
" Switch to normal mode for editing
autocmd BufReadPost,FileReadPost *.gpg set nobin
autocmd BufReadPost,FileReadPost *.gpg let &ch = ch_save|unlet ch_save
autocmd BufReadPost,FileReadPost *.gpg execute ":doautocmd BufReadPost " . expand("%:r")
" Convert all text to encrypted text before writing
autocmd BufWritePre,FileWritePre *.gpg '[,']!gpg --default-recipient-self -ae 2>/dev/null
" Undo the encryption so we are back in the normal text, directly
" after the file has been written.
autocmd BufWritePost,FileWritePost *.gpg u
augroup END
