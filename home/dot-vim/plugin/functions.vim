function! s:FcitxRemote(args) abort
  if !executable('fcitx5-remote')
    return ''
  endif

  let l:cmd = join(map(copy(a:args), 'shellescape(v:val)'), ' ') .. ' 2>/dev/null'
  return trim(system(l:cmd))
endfunction

function! s:FcitxRemoteJob(args) abort
  if !executable('fcitx5-remote')
    return
  endif

  call job_start(a:args, #{out_io: 'null', err_io: 'null'})
endfunction

function! ImActivate(active) abort
  if a:active
    call s:FcitxRemoteJob(['fcitx5-remote', '-o'])
  else
    call s:FcitxRemoteJob(['fcitx5-remote', '-c'])
  endif
endfunction

function! ImStatus() abort
  return s:FcitxRemote(['fcitx5-remote']) ==# '2'
endfunction

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

function! s:PathCompleteToken(line, cursor_col) abort
  let l:start = 0
  let l:quote = ''
  let l:escaped = v:false
  let l:limit = max([0, a:cursor_col - 1])

  for l:i in range(0, l:limit - 1)
    let l:ch = a:line[l:i]
    if l:escaped
      let l:escaped = v:false
      continue
    endif
    if l:ch ==# '\'
      let l:escaped = v:true
      continue
    endif
    if l:quote !=# ''
      if l:ch ==# l:quote
        let l:quote = ''
        let l:start = l:i + 1
      endif
      continue
    endif
    if l:ch ==# '"' || l:ch ==# "'"
      let l:quote = l:ch
      let l:start = l:i + 1
    elseif l:ch =~# '[[:space:]`<>()\[\]{}|,;]'
      let l:start = l:i + 1
    endif
  endfor

  if l:start > 0
    let l:rollback = matchstrpos(strpart(a:line, 0, l:start), '\${\h\w*}$')
    if !empty(l:rollback) && l:rollback[1] >= 0
      let l:start = l:rollback[1]
    endif
  endif

  return #{
        \ start: l:start,
        \ base: strpart(a:line, l:start, l:limit - l:start),
        \ quote: l:quote,
        \ }
endfunction

function! s:PathUnescape(text) abort
  let l:chars = split(a:text, '\zs')
  let l:result = ''
  let l:i = 0

  while l:i < len(l:chars)
    if l:chars[l:i] ==# '\' && l:i + 1 < len(l:chars)
      let l:i += 1
    endif
    let l:result ..= l:chars[l:i]
    let l:i += 1
  endwhile

  return l:result
endfunction

function! s:PathCompleteBaseDir() abort
  let l:bufdir = expand('%:p:h')
  return empty(l:bufdir) ? getcwd() : l:bufdir
endfunction

function! s:StartsWith(text, prefix) abort
  return stridx(a:text, a:prefix) == 0
endfunction

function! s:PathEnvPrefixLength(base) abort
  if !s:StartsWith(a:base, '$')
    return -1
  endif

  if s:StartsWith(a:base, '${')
    let l:end = stridx(a:base, '}/')
    return l:end > 1 ? l:end + 2 : -1
  endif

  let l:slash = stridx(a:base, '/')
  if l:slash <= 1
    return -1
  endif

  let l:name = strpart(a:base, 1, l:slash - 1)
  return l:name =~# '^\h\w*$' ? l:slash + 1 : -1
endfunction

function! s:LooksLikeUri(base) abort
  let l:sep = stridx(a:base, '://')
  if l:sep <= 0
    return v:false
  endif
  return strpart(a:base, 0, l:sep) =~# '^\h\w*$'
endfunction

function! s:PathCompleteShouldTrigger(base) abort
  if empty(a:base)
    return v:false
  endif
  if s:LooksLikeUri(a:base)
    return v:false
  endif
  if s:StartsWith(a:base, '//')
        \ || s:StartsWith(a:base, '/*')
        \ || s:StartsWith(a:base, '*/')
    return v:false
  endif
  if s:StartsWith(a:base, './')
        \ || s:StartsWith(a:base, '../')
        \ || s:StartsWith(a:base, '/')
        \ || s:StartsWith(a:base, '~/')
        \ || s:PathEnvPrefixLength(a:base) > 0
    return v:true
  endif
  return stridx(a:base, '/') >= 0
endfunction

function! s:ResolvePathComplete(base) abort
  let l:base = a:base
  let l:slash = strridx(l:base, '/')
  let l:display_prefix = l:slash >= 0 ? strpart(l:base, 0, l:slash + 1) : ''
  let l:leaf = l:slash >= 0 ? strpart(l:base, l:slash + 1) : l:base
  let l:dir_expr = empty(l:display_prefix) ? '' : substitute(l:display_prefix, '/\+$', '', '')
  let l:dir = ''

  if empty(l:display_prefix)
    let l:dir = s:PathCompleteBaseDir()
  elseif s:StartsWith(l:display_prefix, '~/')
    let l:dir = simplify(expand('~') .. '/' .. l:dir_expr[2:])
  elseif s:StartsWith(l:display_prefix, '${')
    let l:prefix_len = s:PathEnvPrefixLength(l:display_prefix)
    let l:var = strpart(l:display_prefix, 2, l:prefix_len - 4)
    let l:root = getenv(l:var)
    if empty(l:root)
      return {}
    endif
    let l:dir = simplify(fnamemodify(l:root, ':p') .. '/' .. l:dir_expr[l:prefix_len:])
  elseif s:StartsWith(l:display_prefix, '$')
    let l:prefix_len = s:PathEnvPrefixLength(l:display_prefix)
    let l:var = strpart(l:display_prefix, 1, l:prefix_len - 2)
    let l:root = getenv(l:var)
    if empty(l:root)
      return {}
    endif
    let l:dir = simplify(fnamemodify(l:root, ':p') .. '/' .. l:dir_expr[l:prefix_len:])
  elseif s:StartsWith(l:display_prefix, '/')
    let l:dir = simplify('/' .. l:dir_expr[1:])
  else
    let l:dir = simplify(s:PathCompleteBaseDir() .. '/' .. l:dir_expr)
  endif

  return #{
        \ dir: l:dir,
        \ leaf: l:leaf,
        \ display_prefix: l:display_prefix,
        \ show_hidden: l:leaf =~# '^\.',
        \ }
endfunction

function! s:JoinCompletedPath(prefix, name) abort
  if empty(a:prefix)
    return a:name
  endif
  return a:prefix .. a:name
endfunction

function! s:EscapeGlobLiteral(text) abort
  let l:escaped = escape(a:text, '\*?[')
  let l:escaped = substitute(l:escaped, '\]', '\\]', 'g')
  return l:escaped
endfunction

function! s:EscapeCompletedPath(word, quote) abort
  if a:quote !=# ''
    let l:escaped = substitute(a:word, '\\', '\\\\', 'g')
    if a:quote ==# '"'
      let l:escaped = substitute(l:escaped, '"', '\\"', 'g')
    elseif a:quote ==# "'"
      let l:escaped = substitute(l:escaped, "'", "\\'", 'g')
    endif
    return l:escaped
  endif

  let l:escaped = substitute(a:word, '\\', '\\\\', 'g')
  let l:escaped = substitute(l:escaped, ' ', '\\ ', 'g')
  return l:escaped
endfunction

function! PathComplete(findstart, base) abort
  let l:ctx = s:PathCompleteToken(getline('.'), col('.'))

  if a:findstart
    return l:ctx.start
  endif

  let l:base = empty(l:ctx.base) ? a:base : l:ctx.base
  if l:ctx.quote ==# ''
    let l:base = s:PathUnescape(l:base)
  endif

  if !s:PathCompleteShouldTrigger(l:base)
    return []
  endif

  let l:query = s:ResolvePathComplete(l:base)
  if empty(l:query) || !isdirectory(l:query.dir)
    return []
  endif

  let l:matches = []
  let l:pattern = l:query.dir .. '/' .. s:EscapeGlobLiteral(l:query.leaf) .. '*'

  for l:path in glob(l:pattern, 0, 1)
    let l:name = fnamemodify(l:path, ':t')
    if l:name ==# '.' || l:name ==# '..'
      continue
    endif
    let l:isdir = isdirectory(l:path)
    let l:word = s:JoinCompletedPath(l:query.display_prefix, l:name) .. (l:isdir ? '/' : '')
    let l:word = s:EscapeCompletedPath(l:word, l:ctx.quote)

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

function! Gitbranch() abort
  let l:head = gitbranch#name()
  if l:head !=# ''
    let l:head = "\uf126 " .. l:head
  endif
  return l:head
endfunction

function! StatusGitbranch() abort
  let l:branch = Gitbranch()
  return l:branch !=# '' ? ' ' .. l:branch .. ' ' : ''
endfunction

function! StatusModeLabel() abort
  let l:mode = mode()
  if l:mode ==# 'n'
    return 'NORMAL'
  elseif l:mode ==# 'i'
    return 'INSERT'
  elseif l:mode =~# '^[vV]'
    return 'VISUAL'
  elseif l:mode ==# 'R'
    return 'REPLACE'
  elseif l:mode ==# 'c'
    return 'COMMAND'
  elseif l:mode ==# 't'
    return 'TERMINAL'
  endif
  return toupper(l:mode)
endfunction

function! StatusModeHighlight() abort
  let l:mode = mode()
  if l:mode ==# 'i'
    return '%#MyStatusModeInsert#'
  elseif l:mode =~# '^[vV]'
    return '%#MyStatusModeVisual#'
  elseif l:mode ==# 'R'
    return '%#MyStatusModeReplace#'
  elseif l:mode ==# 'c'
    return '%#MyStatusModeCommand#'
  elseif l:mode ==# 't'
    return '%#MyStatusModeTerminal#'
  endif
  return '%#MyStatusModeNormal#'
endfunction

function! StatusPasteLabel() abort
  return &paste ? ' PASTE' : ''
endfunction

function! StatusFileEncoding() abort
  return &fileencoding !=# '' ? &fileencoding : &encoding
endfunction

function! StatusFiletype() abort
  return &filetype !=# '' ? &filetype : 'no ft'
endfunction

function! StatusReadonly() abort
  return &readonly ? '[RO]' : ''
endfunction

function! StatusModified() abort
  return &modified ? '[+]' : ''
endfunction

function! StatusFileSegmentPrefix() abort
  return StatusReadonly() !=# '' ? StatusReadonly() .. ' ' : ''
endfunction

function! StatusTruncateTail(text, max) abort
  if a:max <= 0
    return ''
  endif

  let l:length = strchars(a:text)
  if l:length <= a:max
    return a:text
  endif

  if a:max <= 3
    return repeat('.', a:max)
  endif

  return '...' .. strcharpart(a:text, l:length - (a:max - 3))
endfunction

function! StatusPositionText() abort
  let l:line = line('.')
  let l:total = max([1, line('$')])
  let l:percent = float2nr((100.0 * l:line) / l:total)
  return printf(' %d:%d %d%% ', l:line, col('.'), l:percent)
endfunction

function! StatusInfoText() abort
  return printf('%s | %s | %s', &fileformat, StatusFileEncoding(), StatusFiletype())
endfunction

function! StatusPathMax(show_info) abort
  let l:left = strchars(' ' .. StatusModeLabel() .. StatusPasteLabel() .. ' ')
  let l:left += strchars(StatusGitbranch())
  let l:left += strchars(' ' .. StatusFileSegmentPrefix() .. StatusModified() .. ' ')

  let l:right = strchars(StatusPositionText())
  if a:show_info
    let l:right += strchars(' ' .. StatusInfoText() .. ' ')
  endif

  return winwidth(0) - l:left - l:right
endfunction

function! StatusPath() abort
  let l:path = expand('%:p')
  if l:path ==# ''
    return '[No Name]'
  endif

  let l:path_max = StatusPathMax(v:true)
  if strchars(l:path) > l:path_max && l:path_max <= 20
    let l:path_max = StatusPathMax(v:false)
  endif
  return StatusTruncateTail(l:path, l:path_max)
endfunction

function! StatusInfo() abort
  let l:path = expand('%:p')
  let l:path_max = StatusPathMax(v:true)
  if l:path !=# '' && strchars(l:path) > l:path_max && l:path_max <= 20
    return ''
  endif
  return StatusInfoText()
endfunction
