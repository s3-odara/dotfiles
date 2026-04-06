vim9script

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
