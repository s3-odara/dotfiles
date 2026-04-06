vim9script

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
