function! UpdatePlugins()
  try
    call PackInit()

    if !exists("g:loaded_minpac")
      call writefile(["Error: minpac not loaded"], "minpac_update.log")
      cquit!
    endif

    let g:minpac#opt.status_auto = v:true
    call minpac#update("", {"do": "call PostUpdatePlugins()"})

  catch
    call writefile(["Exception: " . v:exception], "minpac_update.log")
    cquit!
  endtry
endfunction

function! PostUpdatePlugins()
  let l:messages = split(execute("message"), "\n")
  call writefile(l:messages, "minpac_update.log")
  quitall!
endfunction

call UpdatePlugins()
