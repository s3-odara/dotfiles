" -----------------------------------------------------------------------------
" Name:         Orbit
" Description:  Vim port of monoooki/vscode-orbit-theme with yegappan/lsp support
" Author:       OpenAI Codex
" Source:       https://github.com/monoooki/vscode-orbit-theme
" License:      MIT-compatible palette mapping from upstream theme
" -----------------------------------------------------------------------------

if exists('g:colors_name')
  highlight clear
endif

if exists('syntax_on')
  syntax reset
endif

let g:colors_name = 'orbit'

if !(has('termguicolors') && &termguicolors) && !has('gui_running') && &t_Co < 256
  finish
endif

let s:none = 'NONE'
let s:bg0 = '#1B1C1F'
let s:bg1 = '#1D1E21'
let s:bg2 = '#202124'
let s:bg3 = '#222326'
let s:bg4 = '#2A2C31'
let s:fg0 = '#cecece'
"let s:fg3 = '#dc8aa5'
let s:fg3 = '#ce7466'
let s:muted0 = '#b6b6b6'
let s:muted1 = '#a0a0a0'
let s:muted2 = '#8b8b8b'
let s:muted3 = '#757575'
"let s:teal = '#25A693'
let s:teal = '#61b2a3'
let s:teal_dark = '#1F8A7D'
let s:teal_bright = '#37D6C5'
let s:olive = '#95b457'
let s:olive_dark = '#637B20'
let s:olive_bright = '#A8D137'
let s:red = '#f77d6b'
let s:red_term = '#C889C4'
let s:pop_fg = s:fg0
let s:pop_bg = '#4d4d4d'

function! s:hi(group, fg, bg, ...) abort
  let l:style = a:0 >= 1 ? a:1 : s:none
  let l:sp = a:0 >= 2 ? a:2 : s:none
  execute printf(
        \ 'highlight %s guifg=%s guibg=%s gui=%s ctermfg=NONE ctermbg=NONE cterm=%s guisp=%s',
        \ a:group, a:fg, a:bg, l:style, l:style, l:sp
        \ )
endfunction

" Base UI
call s:hi('Normal', s:fg0, s:bg0)
call s:hi('NormalNC', s:fg0, s:bg0)
call s:hi('Terminal', s:fg0, s:bg0)
call s:hi('CursorLine', s:none, s:bg1)
call s:hi('CursorColumn', s:none, s:bg1)
call s:hi('ColorColumn', s:none, s:bg1)
call s:hi('LineNr', s:muted3, s:none)
call s:hi('CursorLineNr', '#AAAAAA', s:none)
call s:hi('SignColumn', s:fg0, s:none)
call s:hi('FoldColumn', s:muted3, s:bg0)
call s:hi('Folded', s:muted1, s:bg1)
call s:hi('EndOfBuffer', s:bg0, s:none)
call s:hi('VertSplit', s:bg4, s:none)
highlight! link WinSeparator VertSplit
call s:hi('StatusLine', s:fg0, s:pop_bg)
call s:hi('StatusLineNC', s:muted0, s:bg1)
call s:hi('TabLine', s:muted0, s:bg1)
call s:hi('TabLineFill', s:muted0, s:bg1)
call s:hi('TabLineSel', s:fg3, s:bg0)
call s:hi('Pmenu', s:pop_fg, s:pop_bg)
call s:hi('PmenuSel', s:pop_fg, s:teal_dark)
call s:hi('PmenuSbar', s:none, s:pop_bg)
call s:hi('PmenuThumb', s:none, s:muted1)
call s:hi('WildMenu', s:pop_fg, s:teal_dark)
call s:hi('NormalFloat', s:pop_fg, s:pop_bg)
call s:hi('FloatBorder', s:pop_fg, s:pop_bg)
call s:hi('Visual', s:bg0, s:olive)
call s:hi('VisualNOS', s:bg0, s:olive)
call s:hi('Search', s:bg0, s:olive_bright)
call s:hi('IncSearch', s:bg0, s:olive)
highlight! link CurSearch IncSearch
call s:hi('MatchParen', s:none, s:bg4)
call s:hi('NonText', s:bg4, s:none)
call s:hi('Whitespace', s:bg4, s:none)
call s:hi('SpecialKey', s:muted0, s:none)
call s:hi('Conceal', s:muted3, s:none)
call s:hi('Directory', s:teal, s:none)
call s:hi('Title', s:teal, s:none, 'bold')
call s:hi('Question', s:fg0, s:none)
call s:hi('ErrorMsg', s:red, s:none, 'underline')
call s:hi('WarningMsg', s:olive, s:none, 'underline')
call s:hi('ModeMsg', s:fg0, s:none, 'bold')
call s:hi('MoreMsg', s:fg0, s:none, 'bold')

" Diagnostics and diff
call s:hi('DiagnosticError', s:red, s:none, 'underline')
call s:hi('DiagnosticSignError', s:olive_bright, s:none, 'underline')
call s:hi('DiagnosticLineError', s:red, s:none, 'underline')
call s:hi('DiagnosticVirtualTextError', s:red, s:none, 'underline')
call s:hi('DiagnosticFloatingError', s:red, s:none, 'underline')
call s:hi('DiagnosticWarn', s:olive_bright, s:none, 'underline')
call s:hi('DiagnosticSignWarn', s:olive_bright, s:none, 'underline')
call s:hi('DiagnosticLineWarn', s:olive_bright, s:none, 'underline')
call s:hi('DiagnosticVirtualTextWarn', s:olive_bright, s:none, 'underline')
call s:hi('DiagnosticFloatingWarn', s:olive_bright, s:none, 'underline')
call s:hi('DiagnosticInfo', s:teal_bright, s:none, 'underline')
call s:hi('DiagnosticSignInfo', s:olive_bright, s:none, 'underline')
call s:hi('DiagnosticLineInfo', s:teal_bright, s:none, 'underline')
call s:hi('DiagnosticVirtualTextInfo', s:teal_bright, s:none, 'underline')
call s:hi('DiagnosticFloatingInfo', s:teal_bright, s:none, 'underline')
call s:hi('DiagnosticHint', s:none, s:none, 'underline')
call s:hi('DiagnosticSignHint', s:olive_bright, s:none, 'underline')
call s:hi('DiagnosticLineHint', s:none, s:none, 'underline')
call s:hi('DiagnosticVirtualTextHint', s:none, s:none, 'underline')
call s:hi('DiagnosticFloatingHint', s:none, s:none, 'underline')
call s:hi('DiagnosticUnderlineError', s:none, s:none, 'undercurl', s:red)
call s:hi('DiagnosticUnderlineWarn', s:none, s:none, 'undercurl', s:olive_bright)
call s:hi('DiagnosticUnderlineInfo', s:none, s:none, 'undercurl', s:teal_bright)
call s:hi('DiagnosticUnderlineHint', s:none, s:none, 'undercurl')
call s:hi('DiffAdd', s:none, '#27311A')
call s:hi('DiffChange', s:none, '#17322E')
call s:hi('DiffDelete', s:none, '#362630')
call s:hi('DiffText', s:bg0, s:teal)

" Syntax groups mapped from Orbit token colors
call s:hi('Comment', s:muted2, s:none)
call s:hi('Constant', s:olive, s:none)
call s:hi('String', s:olive, s:none)
call s:hi('Character', s:olive, s:none)
call s:hi('Number', s:olive, s:none)
call s:hi('Boolean', s:olive, s:none)
call s:hi('Float', s:olive, s:none)
call s:hi('Identifier', s:fg0, s:none)
call s:hi('Function', s:teal, s:none)
call s:hi('Statement', s:fg3, s:none)
call s:hi('Conditional', s:fg3, s:none)
call s:hi('Repeat', s:fg3, s:none)
call s:hi('Label', s:fg3, s:none)
call s:hi('Operator', s:fg0, s:none)
call s:hi('Keyword', s:fg3, s:none)
call s:hi('Exception', s:fg3, s:none)
call s:hi('PreProc', s:fg3, s:none)
call s:hi('Include', s:fg3, s:none, 'italic')
call s:hi('Define', s:fg3, s:none)
call s:hi('Macro', s:fg3, s:none)
call s:hi('PreCondit', s:fg3, s:none)
call s:hi('Type', s:teal, s:none)
call s:hi('StorageClass', s:muted1, s:none)
call s:hi('Structure', s:teal, s:none)
call s:hi('Typedef', s:olive, s:none)
call s:hi('Special', s:teal, s:none)
call s:hi('SpecialChar', s:olive, s:none)
call s:hi('Tag', s:teal, s:none)
call s:hi('Delimiter', s:muted3, s:none)
call s:hi('SpecialComment', s:muted2, s:none)
call s:hi('Debug', s:red_term, s:none)
call s:hi('Underlined', s:teal_bright, s:none, 'underline')
call s:hi('Ignore', s:muted1, s:none)
call s:hi('Error', s:red, s:none, 'bold')
call s:hi('Todo', s:bg0, s:olive, 'bold')

" yegappan/lsp semantic tokens
call s:hi('LspSemanticNamespace', s:teal, s:none)
call s:hi('LspSemanticType', s:olive, s:none)
call s:hi('LspSemanticClass', s:teal, s:none)
call s:hi('LspSemanticEnum', s:teal, s:none)
call s:hi('LspSemanticInterface', s:teal, s:none)
call s:hi('LspSemanticStruct', s:teal, s:none)
call s:hi('LspSemanticTypeParameter', s:olive, s:none)
call s:hi('LspSemanticParameter', s:fg0, s:none)
call s:hi('LspSemanticVariable', s:fg0, s:none)
call s:hi('LspSemanticProperty', s:teal, s:none)
call s:hi('LspSemanticEnumMember', s:olive, s:none)
call s:hi('LspSemanticEvent', s:teal, s:none)
call s:hi('LspSemanticFunction', s:teal, s:none)
call s:hi('LspSemanticMethod', s:teal, s:none)
call s:hi('LspSemanticMacro', s:fg3, s:none)
call s:hi('LspSemanticKeyword', s:fg3, s:none)
call s:hi('LspSemanticModifier', s:muted0, s:none)
call s:hi('LspSemanticComment', s:muted2, s:none)
call s:hi('LspSemanticString', s:olive, s:none)
call s:hi('LspSemanticNumber', s:olive, s:none)
call s:hi('LspSemanticRegexp', s:olive_dark, s:none)
call s:hi('LspSemanticOperator', s:fg0, s:none)
call s:hi('LspSemanticDecorator', s:fg3, s:none)

" Compatibility links for older LSP highlight group names
highlight! link LspDiagnosticsDefaultError DiagnosticError
highlight! link LspDiagnosticsDefaultWarning DiagnosticWarn
highlight! link LspDiagnosticsDefaultInformation DiagnosticInfo
highlight! link LspDiagnosticsDefaultHint DiagnosticHint
highlight! link LspDiagnosticsFloatingError DiagnosticFloatingError
highlight! link LspDiagnosticsFloatingWarning DiagnosticFloatingWarn
highlight! link LspDiagnosticsFloatingInformation DiagnosticFloatingInfo
highlight! link LspDiagnosticsFloatingHint DiagnosticFloatingHint
highlight! link LspDiagnosticsVirtualTextError DiagnosticVirtualTextError
highlight! link LspDiagnosticsVirtualTextWarning DiagnosticVirtualTextWarn
highlight! link LspDiagnosticsVirtualTextInformation DiagnosticVirtualTextInfo
highlight! link LspDiagnosticsVirtualTextHint DiagnosticVirtualTextHint
highlight! link LspDiagnosticsSignError DiagnosticSignError
highlight! link LspDiagnosticsSignWarning DiagnosticSignWarn
highlight! link LspDiagnosticsSignInformation DiagnosticSignInfo
highlight! link LspDiagnosticsSignHint DiagnosticSignHint
highlight! link LspDiagSignErrorText DiagnosticSignError
highlight! link LspDiagSignWarningText DiagnosticSignWarn
highlight! link LspDiagSignInfoText DiagnosticSignInfo
highlight! link LspDiagSignHintText DiagnosticSignHint
highlight! link LspDiagInlineError DiagnosticLineError
highlight! link LspDiagInlineWarning DiagnosticLineWarn
highlight! link LspDiagInlineInfo DiagnosticLineInfo
highlight! link LspDiagInlineHint DiagnosticLineHint
highlight! link LspDiagVirtualTextError DiagnosticVirtualTextError
highlight! link LspDiagVirtualTextWarning DiagnosticVirtualTextWarn
highlight! link LspDiagVirtualTextInfo DiagnosticVirtualTextInfo
highlight! link LspDiagVirtualTextHint DiagnosticVirtualTextHint
highlight! link DiagnosticWarning DiagnosticWarn

" Extra groups commonly used by plugins and filetypes
highlight! link htmlTag Tag
highlight! link htmlEndTag Tag
highlight! link htmlTagName Tag
highlight! link htmlArg Identifier
highlight! link xmlTag Tag
highlight! link xmlEndTag Tag
highlight! link xmlTagName Tag
highlight! link cssBraces Delimiter
highlight! link cssClassName Identifier
highlight! link cssIdentifier Identifier
highlight! link cssProp LspSemanticProperty
highlight! link jsonKeyword LspSemanticProperty
highlight! link yamlBlockMappingKey LspSemanticProperty
highlight! link tomlKey LspSemanticProperty

let g:terminal_ansi_colors = [
      \ s:bg0, s:red_term, '#93BA2F', '#B3C73F',
      \ '#1F8A7D', '#C8A1E8', s:teal, '#E6E8ED',
      \ s:bg4, '#E3B8EA', '#C5E152', '#D5EB6D',
      \ '#2CC0B1', '#E2C4FF', s:teal_bright, '#FFFFFF'
      \ ]
