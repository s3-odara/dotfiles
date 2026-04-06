vim9script

def SetupStatuslineHighlights()
  highlight StatusLineNC cterm=NONE ctermfg=245 ctermbg=237 gui=NONE guifg=#8a9199 guibg=#2d323b
  highlight MyStatusModeNormal cterm=bold ctermfg=235 ctermbg=110 gui=bold guifg=#1f2430 guibg=#73b8ff
  highlight MyStatusModeInsert cterm=bold ctermfg=235 ctermbg=150 gui=bold guifg=#1f2430 guibg=#95e6cb
  highlight MyStatusModeVisual cterm=bold ctermfg=235 ctermbg=216 gui=bold guifg=#1f2430 guibg=#f6c177
  highlight MyStatusModeReplace cterm=bold ctermfg=235 ctermbg=203 gui=bold guifg=#1f2430 guibg=#f28779
  highlight MyStatusModeCommand cterm=bold ctermfg=235 ctermbg=222 gui=bold guifg=#1f2430 guibg=#ffd173
  highlight MyStatusModeTerminal cterm=bold ctermfg=235 ctermbg=117 gui=bold guifg=#1f2430 guibg=#73d0ff
  highlight MyStatusGit cterm=NONE ctermfg=252 ctermbg=239 gui=NONE guifg=#e6e1cf guibg=#3a3f4b
  highlight MyStatusFile cterm=NONE ctermfg=252 ctermbg=237 gui=NONE guifg=#e6e1cf guibg=#2d323b
  highlight MyStatusInfo cterm=NONE ctermfg=250 ctermbg=235 gui=NONE guifg=#c5cdd9 guibg=#1f2430
  highlight MyStatusPosition cterm=NONE ctermfg=235 ctermbg=109 gui=NONE guifg=#1f2430 guibg=#7aa2b8
enddef

def SetupStatusline()
  &statusline = join([
    '%{%g:StatuslineModeHighlight()%}',
    ' %{g:StatuslineModeText()}',
    '%#MyStatusGit#',
    ' %{g:StatuslineBranch()}',
    '%#MyStatusFile#',
    ' %<%{g:StatuslineFileSegment()}',
    '%#MyStatusInfo#',
    '%=',
    ' %{g:StatuslineInfo()}',
    '%#MyStatusPosition#',
    ' %l:%c',
    ' %p%% ',
  ], '')
enddef

augroup MyStatusline
  autocmd!
  autocmd ColorScheme * call SetupStatuslineHighlights()
augroup END

SetupStatuslineHighlights()
SetupStatusline()
