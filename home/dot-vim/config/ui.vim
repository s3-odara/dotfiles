vim9script

# ColorScheme
def g:ApplyTransparentBackground()
  if get(g:, 'colors_name', '') !=# 'odara'
    return
  endif

  highlight Normal ctermbg=NONE guibg=NONE
  highlight NonText ctermbg=NONE guibg=NONE
  highlight SpecialKey ctermbg=NONE guibg=NONE
  highlight EndOfBuffer ctermbg=NONE guibg=NONE
enddef

set termguicolors
set background=dark

&t_SI = "\<Esc>[3 q" # Start Insert
&t_SR = "\<Esc>[3 q" # StartReplace
&t_EI = "\<Esc>[3 q" # End Insert

augroup TransparentBG
  autocmd!
  autocmd ColorScheme * call g:ApplyTransparentBackground()
augroup END
