augroup fcitx5_control_fn
  autocmd!

  function! s:FcitxOnInsertLeave() abort
    let w:im_name = trim(system('fcitx5-remote -n'))
    call job_start(['fcitx5-remote', '-c'])
  endfunction

  function! s:FcitxOnInsertEnter() abort
    if exists('w:im_name') && w:im_name !=# 'keyboard-us'
      call job_start(['fcitx5-remote', '-o'])
    endif
  endfunction

  autocmd InsertLeave * call s:FcitxOnInsertLeave()
  autocmd InsertEnter * call s:FcitxOnInsertEnter()
augroup END

augroup vimrc-auto-mkdir
  autocmd!

  function! s:auto_mkdir(dir, force) abort
    if !isdirectory(a:dir) && (a:force ||
    \   input(printf('"%s" does not exist. Create? [y/N]', a:dir)) =~? '^y\%[es]$')
      call mkdir(iconv(a:dir, &encoding, &termencoding), 'p')
    endif
  endfunction

  autocmd BufWritePre * call s:auto_mkdir(expand('<afile>:p:h'), v:cmdbang)
augroup END

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

function! Osc52Copy() abort
  let l:save_reg = @"
  normal! gvy
  let l:content = @"
  let @" = l:save_reg
  if len(l:content) == 0
    echo "Nothing to copy"
    return
  endif

  let l:b64 = system('base64 | tr -d "\n"', l:content)
  if len(l:b64) > 100000
    redraw
    echohl WarningMsg
    echo "Warning: Content too large for OSC 52 copy."
    echohl None
    return
  endif

  let l:seq = "\x1b]52;c;" . l:b64 . "\x07"
  call writefile([l:seq], "/dev/tty", "b")
  redraw!
  echo "Copied to clipboard (OSC 52)"
endfunction
