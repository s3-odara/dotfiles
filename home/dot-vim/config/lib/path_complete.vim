vim9script

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
