vim9script

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

inoremap <expr> ( g:AutoPairOpen('(', ')')
inoremap <expr> [ g:AutoPairOpen('[', ']')
inoremap <expr> { g:AutoPairOpen('{', '}')
inoremap <expr> ' g:AutoPairSymmetric("'")
inoremap <expr> " g:AutoPairSymmetric('"')
inoremap <expr> ) g:AutoPairClose(')')
inoremap <expr> ] g:AutoPairClose(']')
inoremap <expr> } g:AutoPairClose('}')
