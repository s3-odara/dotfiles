vim9script

def g:Osc52CopySelection()
  var lines = getregion(getpos("'<"), getpos("'>"), {
    type: visualmode(),
    exclusive: &selection ==# 'exclusive',
  })

  var b64 = lines->str2blob()->base64_encode()
  echoraw($"\x1b]52;c;{b64}\x07")
  echomsg 'Copied!'
enddef

xnoremap <silent> "+y :<C-u>call g:Osc52CopySelection()<CR>
