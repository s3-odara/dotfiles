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

function! ScrollCompleteInfo(cmd, fallback) abort
  let l:id = popup_findinfo()
  if l:id > 0 && pumvisible()
    let l:pos = popup_getpos(l:id)
    let l:firstline = get(l:pos, 'firstline', 1)
    if a:cmd ==# "\<C-e>"
      call popup_setoptions(l:id, #{firstline: l:firstline + 1})
    elseif a:cmd ==# "\<C-y>"
      call popup_setoptions(l:id, #{firstline: max([1, l:firstline - 1])})
    endif
    return ''
  endif
  return a:fallback
endfunction

function! InVsnipSession() abort
  try
    return vsnip#jumpable(1) || vsnip#jumpable(-1)
  catch
    return v:false
  endtry
endfunction

function! PathComplete(findstart, base) abort
  if a:findstart
    let l:line = getline('.')
    let l:col = col('.') - 1

    while l:col > 0 && l:line[l:col - 1] !~# '[[:space:]"''`<>()\[\]{}|,;]'
      let l:col -= 1
    endwhile

    return l:col
  endif

  if a:base !~# '^\./'
        \ && a:base !~# '^\.\./'
        \ && a:base !~# '^/'
        \ && stridx(a:base, '~/') != 0
        \ && stridx(a:base, '/') == -1
    return []
  endif

  let l:expanded = stridx(a:base, '~/') == 0 ? expand(a:base) : a:base
  let l:dir = fnamemodify(l:expanded, ':h')
  let l:leaf = fnamemodify(l:expanded, ':t')
  let l:prefix = l:dir ==# '.' ? '' : l:dir .. '/'
  let l:matches = []

  if !isdirectory(empty(l:dir) ? '.' : l:dir)
    return []
  endif

  for l:path in glob(l:prefix .. '*', 0, 1)
    let l:name = fnamemodify(l:path, ':t')
    if l:name !~# '^' .. escape(l:leaf, '\')
      continue
    endif

    let l:isdir = isdirectory(l:path)
    let l:word = l:prefix .. l:name .. (l:isdir ? '/' : '')
    if stridx(a:base, '~/') == 0
      let l:home = expand('~/')
      if stridx(l:word, l:home) == 0
        let l:word = '~/' .. l:word[strlen(l:home):]
      endif
    endif

    call add(l:matches, #{
          \ word: l:word,
          \ abbr: l:name .. (l:isdir ? '/' : ''),
          \ menu: l:isdir ? '[dir]' : '[path]',
          \ })
  endfor

  return {'words': l:matches, 'refresh': 'always'}
endfunction

function! SmartOpenPair(open, close) abort
  let l:col = col('.')
  let l:line = getline('.')
  let l:next = l:col <= len(l:line) ? l:line[l:col - 1] : ''
  if l:next !=# '' && l:next !~# '\s'
    return a:open
  endif
  return a:open . a:close . "\<Left>"
endfunction

function! SmartClosePair(close) abort
  let l:col = col('.')
  let l:line = getline('.')
  let l:next = l:col <= len(l:line) ? l:line[l:col - 1] : ''
  if l:next ==# a:close
    return "\<Right>"
  endif
  return a:close
endfunction

function! TyposCodeAction(...) abort
  let l:query = get(a:, 1, '')
  let l:lspserver = lsp#buffer#CurbufGetServerByName('typos-lsp')
  if empty(l:lspserver)
    echohl ErrorMsg
    echo 'typos-lsp is not attached to this buffer'
    echohl None
    return
  endif
  if !get(l:lspserver, 'running', v:false)
    echohl ErrorMsg
    echo 'typos-lsp is not running'
    echohl None
    return
  endif
  if !get(l:lspserver, 'ready', v:false)
    echohl ErrorMsg
    echo 'typos-lsp is not ready'
    echohl None
    return
  endif

  let l:view = winsaveview()
  call cursor(line('.'), 1)
  call l:lspserver.codeAction(expand('%'), line('.'), line('.'), l:query)
  call winrestview(l:view)
endfunction
