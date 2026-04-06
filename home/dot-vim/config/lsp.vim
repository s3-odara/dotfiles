vim9script

def ApplyLspOptions()
  g:LspOptionsSet({
    'autoComplete': v:false,
    'semanticHighlight': v:true,
    'snippetSupport': v:true,
    'vsnipSupport': v:true,
    'condensedCompletionMenu': v:true,
    'usePopupInCodeAction': v:true,
  })
enddef

augroup lsp_setup
  autocmd!
  autocmd User LspSetup call ApplyLspOptions()
  autocmd User LspSetup call g:RegisterLspServers()
augroup END
