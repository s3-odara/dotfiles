function UpdatePlugins()
  call PackInit()

  if !exists("g:loaded_minpac")
    call setline(1, split(execute("message"), "\n"))
    call append("$", "Failed to load minpac")
    %print
    cquit!
  endif

  let g:minpac#opt.status_auto = v:true

  call minpac#update("", {"do": "call PostUpdatePlugins()"})
endfunction

function PostUpdatePlugins()
  %print
  quitall!
endfunction
