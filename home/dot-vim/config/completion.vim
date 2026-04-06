vim9script

def SetupCmdlineAutocomplete()
  if has('nvim') || !has('patch-9.1.1576') || !has('autocmd')
    return
  endif

  set wildmenu
  set wildmode=noselect:lastused,full
  # noselectを設定していない場合、補完が呼び出された時点で候補が自動選択される。
  # これにより、コマンドを手動で編集できなくなる。

  augroup MyCmdlineAutocomplete
    autocmd!
    #  コマンドラインの内容が変更されたときに、自動で補完を呼び出す。
    autocmd CmdlineChanged [:/?] call wildtrigger()
  augroup END
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

set autocomplete
set autocompletedelay=200
set completeopt=menuone,fuzzy,popup
set complete=o,Fvsnip#completefunc,FPathComplete,k^2,.^5,w^5,b^5
set wildmenu
set wildoptions+=fuzzy

source ~/.vim/config/lib/path_complete.vim

# Completion / insert helpers
inoremap <expr> <PageDown> g:CompletionPopupScroll("\<C-e>", "\<PageDown>")
inoremap <expr> <PageUp> g:CompletionPopupScroll("\<C-y>", "\<PageUp>")
inoremap <C-x><C-d> <C-x><C-k>
# thesaurus complete
inoremap <C-t> <C-x><C-t>

SetupCmdlineAutocomplete()
