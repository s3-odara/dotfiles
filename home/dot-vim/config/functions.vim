vim9script

def FcitxRemote(args: list<string>): string
  if !executable('fcitx5-remote')
    return ''
  endif

  var cmd = join(mapnew(copy(args), (_, value) => shellescape(value)), ' ') .. ' 2>/dev/null'
  return trim(system(cmd))
enddef

def FcitxRemoteJob(args: list<string>)
  if !executable('fcitx5-remote')
    return
  endif

  job_start(args, {out_io: 'null', err_io: 'null'})
enddef

def g:ImeActivate(active: bool): number
  FcitxRemoteJob(active ? ['fcitx5-remote', '-o'] : ['fcitx5-remote', '-c'])
  return 0
enddef

def g:ImeStatus(): number
  return FcitxRemote(['fcitx5-remote']) ==# '2' ? 1 : 0
enddef

def AutoMkdir(dir: string, force: bool)
  if isdirectory(dir)
    return
  endif
  if !force && input($'"{dir}" does not exist. Create? [y/N]') !~? '^y\%[es]$'
    return
  endif
  mkdir(iconv(dir, &encoding, &termencoding), 'p')
enddef

augroup vimrc_auto_mkdir
  autocmd!
  autocmd BufWritePre * call AutoMkdir(expand('<afile>:p:h'), !!v:cmdbang)
augroup END

augroup encrypted
  autocmd!
  autocmd BufReadPre,FileReadPre *.gpg set viminfo=
  autocmd BufReadPre,FileReadPre *.gpg set noswapfile
  autocmd BufReadPre,FileReadPre *.gpg set noundofile
  autocmd BufReadPre,FileReadPre *.gpg set bin
  autocmd BufReadPre,FileReadPre *.gpg let b:gpg_cmdheight_save = &cmdheight | set cmdheight=2
  autocmd BufReadPost,FileReadPost *.gpg '[,']!gpg --decrypt 2> /dev/null
  autocmd BufReadPost,FileReadPost *.gpg set nobin
  autocmd BufReadPost,FileReadPost *.gpg let &cmdheight = get(b:, 'gpg_cmdheight_save', &cmdheight) | unlet! b:gpg_cmdheight_save
  autocmd BufReadPost,FileReadPost *.gpg execute ':doautocmd BufReadPost ' .. expand('%:r')
  autocmd BufWritePre,FileWritePre *.gpg '[,']!gpg --default-recipient-self -ae 2>/dev/null
  autocmd BufWritePost,FileWritePost *.gpg undo
augroup END

def g:Osc52CopySelection()
  var saveReg = @"
  normal! gvy
  var content = @"
  @" = saveReg
  if len(content) == 0
    echo 'Nothing to copy'
    return
  endif

  var b64 = system('base64 | tr -d "\n"', content)
  if len(b64) > 100000
    redraw
    echohl WarningMsg
    echo 'Warning: Content too large for OSC 52 copy.'
    echohl None
    return
  endif

  var seq = "\x1b]52;c;" .. b64 .. "\x07"
  writefile([seq], '/dev/tty', 'b')
  redraw!
  echo 'Copied to clipboard (OSC 52)'
enddef

def g:CompletionPopupScroll(cmd: string, fallback: string): string
  var id = popup_findinfo()
  if id > 0 && pumvisible()
    var pos = popup_getpos(id)
    var firstline = get(pos, 'firstline', 1)
    if cmd ==# "\<C-e>"
      popup_setoptions(id, {firstline: firstline + 1})
    elseif cmd ==# "\<C-y>"
      popup_setoptions(id, {firstline: max([1, firstline - 1])})
    endif
    return ''
  endif
  return fallback
enddef

def g:VsnipSessionActive(): bool
  try
    return vsnip#jumpable(1) || vsnip#jumpable(-1)
  catch
    return v:false
  endtry
enddef

def PathCompleteToken(lineText: string, cursorCol: number): dict<any>
  var start = 0
  var quote = ''
  var escaped = v:false
  var limit = max([0, cursorCol - 1])

  for i in range(0, limit - 1)
    var ch = lineText[i]
    if escaped
      escaped = v:false
      continue
    endif
    if ch ==# '\'
      escaped = v:true
      continue
    endif
    if quote !=# ''
      if ch ==# quote
        quote = ''
        start = i + 1
      endif
      continue
    endif
    if ch ==# '"' || ch ==# "'"
      quote = ch
      start = i + 1
    elseif ch =~# '[[:space:]`<>()\[\]{}|,;]'
      start = i + 1
    endif
  endfor

  if start > 0
    var rollback = matchstrpos(strpart(lineText, 0, start), '\${\h\w*}$')
    if !empty(rollback) && rollback[1] >= 0
      start = rollback[1]
    endif
  endif

  return {
    start: start,
    base: strpart(lineText, start, limit - start),
    quote: quote,
  }
enddef

def PathUnescape(text: string): string
  var chars = split(text, '\zs')
  var result = ''
  var i = 0

  while i < len(chars)
    if chars[i] ==# '\' && i + 1 < len(chars)
      i += 1
    endif
    result ..= chars[i]
    i += 1
  endwhile

  return result
enddef

def PathCompleteBaseDir(): string
  var bufdir = expand('%:p:h')
  return empty(bufdir) ? getcwd() : bufdir
enddef

def StartsWith(text: string, prefix: string): bool
  return stridx(text, prefix) == 0
enddef

def PathEnvPrefixLength(base: string): number
  if !StartsWith(base, '$')
    return -1
  endif

  if StartsWith(base, '${')
    var end = stridx(base, '}/')
    return end > 1 ? end + 2 : -1
  endif

  var slash = stridx(base, '/')
  if slash <= 1
    return -1
  endif

  var name = strpart(base, 1, slash - 1)
  return name =~# '^\h\w*$' ? slash + 1 : -1
enddef

def LooksLikeUri(base: string): bool
  var sep = stridx(base, '://')
  if sep <= 0
    return v:false
  endif
  return strpart(base, 0, sep) =~# '^\h\w*$'
enddef

def PathCompleteShouldTrigger(base: string): bool
  if empty(base)
    return v:false
  endif
  if LooksLikeUri(base)
    return v:false
  endif
  if StartsWith(base, '//') || StartsWith(base, '/*') || StartsWith(base, '*/')
    return v:false
  endif
  if StartsWith(base, './')
      || StartsWith(base, '../')
      || StartsWith(base, '/')
      || StartsWith(base, '~/')
      || PathEnvPrefixLength(base) > 0
    return v:true
  endif
  return stridx(base, '/') >= 0
enddef

def ResolvePathComplete(base: string): dict<any>
  var slash = strridx(base, '/')
  var displayPrefix = slash >= 0 ? strpart(base, 0, slash + 1) : ''
  var leaf = slash >= 0 ? strpart(base, slash + 1) : base
  var dirExpr = empty(displayPrefix) ? '' : substitute(displayPrefix, '/\+$', '', '')
  var dir = ''

  if empty(displayPrefix)
    dir = PathCompleteBaseDir()
  elseif StartsWith(displayPrefix, '~/')
    dir = simplify(expand('~') .. '/' .. dirExpr[2 :])
  elseif StartsWith(displayPrefix, '${')
    var prefixLen = PathEnvPrefixLength(displayPrefix)
    var varName = strpart(displayPrefix, 2, prefixLen - 4)
    var root = getenv(varName)
    if empty(root)
      return {}
    endif
    dir = simplify(fnamemodify(root, ':p') .. '/' .. dirExpr[prefixLen :])
  elseif StartsWith(displayPrefix, '$')
    var prefixLen = PathEnvPrefixLength(displayPrefix)
    var varName = strpart(displayPrefix, 1, prefixLen - 2)
    var root = getenv(varName)
    if empty(root)
      return {}
    endif
    dir = simplify(fnamemodify(root, ':p') .. '/' .. dirExpr[prefixLen :])
  elseif StartsWith(displayPrefix, '/')
    dir = simplify('/' .. dirExpr[1 :])
  else
    dir = simplify(PathCompleteBaseDir() .. '/' .. dirExpr)
  endif

  return {
    dir: dir,
    leaf: leaf,
    display_prefix: displayPrefix,
    show_hidden: leaf =~# '^\.',
  }
enddef

def JoinCompletedPath(prefix: string, name: string): string
  return empty(prefix) ? name : prefix .. name
enddef

def EscapeGlobLiteral(text: string): string
  var escaped = escape(text, '\*?[')
  escaped = substitute(escaped, '\]', '\\]', 'g')
  return escaped
enddef

def EscapeCompletedPath(word: string, quote: string): string
  var escaped = substitute(word, '\\', '\\\\', 'g')
  if quote ==# ''
    return substitute(escaped, ' ', '\\ ', 'g')
  endif
  if quote ==# '"'
    return substitute(escaped, '"', '\\"', 'g')
  endif
  if quote ==# "'"
    return substitute(escaped, "'", "\\'", 'g')
  endif
  return escaped
enddef

def g:PathComplete(findstart: bool, base: string): any
  var ctx = PathCompleteToken(getline('.'), col('.'))

  if findstart
    return ctx.start
  endif

  var completeBase = empty(ctx.base) ? base : ctx.base
  if ctx.quote ==# ''
    completeBase = PathUnescape(completeBase)
  endif

  if !PathCompleteShouldTrigger(completeBase)
    return []
  endif

  var query = ResolvePathComplete(completeBase)
  if empty(query) || !isdirectory(query.dir)
    return []
  endif

  var matches: list<dict<string>> = []
  var pattern = query.dir .. '/' .. EscapeGlobLiteral(query.leaf) .. '*'

  for path in glob(pattern, 0, 1)
    var name = fnamemodify(path, ':t')
    if name ==# '.' || name ==# '..'
      continue
    endif
    var isdir = isdirectory(path)
    var word = JoinCompletedPath(query.display_prefix, name) .. (isdir ? '/' : '')
    word = EscapeCompletedPath(word, ctx.quote)
    add(matches, {
      word: word,
      abbr: name .. (isdir ? '/' : ''),
      menu: isdir ? '[dir]' : '[path]',
    })
  endfor

  return {
    words: matches,
    refresh: 'always',
  }
enddef

def NextCharAtCursor(): string
  var cursorCol = col('.')
  var lineText = getline('.')
  return cursorCol <= len(lineText) ? lineText[cursorCol - 1] : ''
enddef

def TextUntilWhitespaceAtCursor(): string
  var cursorCol = col('.')
  var lineText = getline('.')
  return matchstr(strpart(lineText, cursorCol - 1), '^\S*')
enddef

def AutoPairSegmentAllowed(text: string): bool
  for ch in split(text, '\zs')
    if index([')', ']', '}', "'", '"'], ch) < 0
      return v:false
    endif
  endfor
  return v:true
enddef

def g:AutoPairOpen(open: string, close: string): string
  var segment = TextUntilWhitespaceAtCursor()
  if !empty(segment) && !AutoPairSegmentAllowed(segment)
    return open
  endif
  return open .. close .. "\<Left>"
enddef

def g:AutoPairSymmetric(char: string): string
  return NextCharAtCursor() ==# char ? "\<Right>" : g:AutoPairOpen(char, char)
enddef

def g:AutoPairClose(close: string): string
  return NextCharAtCursor() ==# close ? "\<Right>" : close
enddef

def ShowError(message: string)
  echohl ErrorMsg
  echo message
  echohl None
enddef

def g:TyposCodeAction(...queryList: list<any>)
  var query = get(queryList, 0, '')
  var lspserver = lsp#buffer#CurbufGetServerByName('typos-lsp')
  if empty(lspserver)
    ShowError('typos-lsp is not attached to this buffer')
    return
  endif
  if !get(lspserver, 'running', v:false)
    ShowError('typos-lsp is not running')
    return
  endif
  if !get(lspserver, 'ready', v:false)
    ShowError('typos-lsp is not ready')
    return
  endif

  var view = winsaveview()
  cursor(line('.'), 1)
  lspserver.codeAction(expand('%'), line('.'), line('.'), query)
  winrestview(view)
enddef

def BranchText(): string
  var head = gitbranch#name()
  return empty(head) ? '' : head
enddef

def ModeLabel(): string
  var current = mode()
  if current ==# 'n'
    return 'NORMAL'
  elseif current ==# 'i'
    return 'INSERT'
  elseif current =~# '^[vV]'
    return 'VISUAL'
  elseif current ==# 'R'
    return 'REPLACE'
  elseif current ==# 'c'
    return 'COMMAND'
  elseif current ==# 't'
    return 'TERMINAL'
  endif
  return toupper(current)
enddef

def PasteLabel(): string
  return &paste ? ' PASTE' : ''
enddef

def FileEncodingLabel(): string
  return !empty(&fileencoding) ? &fileencoding : &encoding
enddef

def FiletypeLabel(): string
  return !empty(&filetype) ? &filetype : 'no ft'
enddef

def ReadonlyLabel(): string
  return &readonly ? '[RO]' : ''
enddef

def ModifiedLabel(): string
  return &modified ? '[+]' : ''
enddef

def TruncateTail(text: string, maxWidth: number): string
  if maxWidth <= 0
    return ''
  endif

  var length = strchars(text)
  if length <= maxWidth
    return text
  endif

  if maxWidth <= 3
    return repeat('.', maxWidth)
  endif

  return '...' .. strcharpart(text, length - (maxWidth - 3))
enddef

def PositionText(): string
  var currentLine = line('.')
  var total = max([1, line('$')])
  var percent = float2nr((100.0 * currentLine) / total)
  return printf(' %d:%d %d%% ', currentLine, col('.'), percent)
enddef

def InfoText(): string
  return printf('%s | %s | %s', &fileformat, FileEncodingLabel(), FiletypeLabel())
enddef

def FileSegmentFixedWidth(): number
  var prefix = ReadonlyLabel()
  if !empty(prefix)
    prefix ..= ' '
  endif
  return strchars(prefix .. ModifiedLabel() .. ' ')
enddef

def BranchSegmentText(): string
  var branch = BranchText()
  return empty(branch) ? '' : branch .. ' '
enddef

def PathMax(showInfo: bool): number
  var left = strchars(' ' .. ModeLabel() .. PasteLabel() .. ' ')
  if !empty(BranchText())
    left += 1 + strchars(BranchSegmentText())
  endif
  left += 1 + FileSegmentFixedWidth()

  var right = strchars(PositionText())
  if showInfo
    right += 1 + strchars(InfoText() .. ' ')
  endif

  return winwidth(0) - left - right
enddef

def PathText(showInfo: bool): string
  var path = expand('%:p')
  if empty(path)
    return '[No Name]'
  endif

  var pathMax = PathMax(showInfo)
  if strchars(path) > pathMax && pathMax <= 20 && showInfo
    pathMax = PathMax(v:false)
  endif
  return TruncateTail(path, pathMax)
enddef

def g:StatuslineModeHighlight(): string
  var current = mode()
  if current ==# 'i'
    return '%#MyStatusModeInsert#'
  elseif current =~# '^[vV]'
    return '%#MyStatusModeVisual#'
  elseif current ==# 'R'
    return '%#MyStatusModeReplace#'
  elseif current ==# 'c'
    return '%#MyStatusModeCommand#'
  elseif current ==# 't'
    return '%#MyStatusModeTerminal#'
  endif
  return '%#MyStatusModeNormal#'
enddef

def g:StatuslineModeText(): string
  return ModeLabel() .. PasteLabel() .. ' '
enddef

def g:StatuslineBranch(): string
  return BranchSegmentText()
enddef

def g:StatuslineFileSegment(): string
  var prefix = ReadonlyLabel()
  if !empty(prefix)
    prefix ..= ' '
  endif
  return prefix .. PathText(v:true) .. ModifiedLabel() .. ' '
enddef

def g:StatuslineInfo(): string
  var path = expand('%:p')
  var pathMax = PathMax(v:true)
  if !empty(path) && strchars(path) > pathMax && pathMax <= 20
    return ''
  endif
  return InfoText() .. ' '
enddef
