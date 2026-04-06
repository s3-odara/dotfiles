vim9script

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
  echoraw(seq)
  redraw!
  echo 'Copied to clipboard (OSC 52)'
enddef

xnoremap <silent> "+y :<C-u>call g:Osc52CopySelection()<CR>
nnoremap "+p :let @"=substitute(system("wl-paste --no-newline"), '\r', '', 'g')<CR>p
nnoremap "*p :let @"=substitute(system("wl-paste --no-newline --primary"), '\r', '', 'g')<CR>p
