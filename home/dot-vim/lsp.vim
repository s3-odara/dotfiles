augroup lsp_setup
  autocmd!
  autocmd User LspSetup call LspOptionsSet(#{
        \ autoComplete: v:false,
        \ snippetSupport: v:true,
        \ vsnipSupport: v:true,
        \ condensedCompletionMenu: v:true,
        \ })
  autocmd User LspSetup call s:RegisterLspServers()
augroup END

function! s:MozukuServerPath() abort
  let l:path = exepath('mozuku-lsp')
  if !empty(l:path)
    return l:path
  endif

  let l:local_path = expand('~/.local/bin/mozuku-lsp')
  if executable(l:local_path)
    return l:local_path
  endif

  return ''
endfunction

function! s:MozukuLanguageId() abort
  if &filetype ==# 'text'
    return 'japanese'
  endif
  if &filetype ==# 'tex' || &filetype ==# 'plaintex'
    return 'latex'
  endif
  return &filetype
endfunction

function! s:MozukuInitOptions() abort
  let l:warnings = get(g:, 'mozuku_warnings', {})
  let l:rules = get(g:, 'mozuku_rules', {})
  let l:default_dicdir = isdirectory(expand('~/.local/lib/mecab/dic/ipadic'))
        \ ? expand('~/.local/lib/mecab/dic/ipadic')
        \ : ''

  let l:warning_defaults = #{
        \ particleDuplicate: v:true,
        \ particleSequence: v:true,
        \ particleMismatch: v:true,
        \ sentenceStructure: v:false,
        \ styleConsistency: v:false,
        \ redundancy: v:false,
        \ }
  call extend(l:warning_defaults, l:warnings, 'force')

  let l:rule_defaults = #{
        \ commaLimit: v:true,
        \ adversativeGa: v:true,
        \ duplicateParticleSurface: v:true,
        \ adjacentParticles: v:true,
        \ conjunctionRepeat: v:true,
        \ raDropping: v:true,
        \ commaLimitMax: 3,
        \ adversativeGaMax: 1,
        \ duplicateParticleSurfaceMaxRepeat: 1,
        \ adjacentParticlesMaxRepeat: 1,
        \ conjunctionRepeatMax: 1,
        \ }
  call extend(l:rule_defaults, l:rules, 'force')

  return #{
        \ mozuku: #{
        \   mecab: #{
        \     dicdir: get(g:, 'mozuku_mecab_dicdir', l:default_dicdir),
        \     charset: get(g:, 'mozuku_mecab_charset', 'UTF-8'),
        \   },
        \   analysis: #{
        \     enableCaboCha: get(g:, 'mozuku_analysis_enable_cabocha', executable('cabocha') ? v:true : v:false),
        \     grammarCheck: get(g:, 'mozuku_analysis_grammar_check', v:true),
        \     minJapaneseRatio: get(g:, 'mozuku_analysis_min_japanese_ratio', 0.1),
        \     warningMinSeverity: get(g:, 'mozuku_analysis_warning_min_severity', 2),
        \     warnings: l:warning_defaults,
        \     rules: l:rule_defaults,
        \   },
        \ },
        \ }
endfunction

function! s:FirstExecutable(candidates) abort
  for l:candidate in a:candidates
    if executable(l:candidate)
      return l:candidate
    endif
  endfor

  return ''
endfunction

function! s:AddLspServerIfExecutable(servers, name, filetypes, executable_names, args) abort
  let l:executable_name = s:FirstExecutable(a:executable_names)
  if !empty(l:executable_name)
    call add(a:servers, #{
          \ name: a:name,
          \ filetype: a:filetypes,
          \ path: exepath(l:executable_name),
          \ args: a:args,
          \ })
  endif
endfunction

function! s:RegisterLspServers() abort
  let l:servers = []

  call s:AddLspServerIfExecutable(l:servers, 'denols',
        \ ['javascript', 'javascriptreact', 'typescript', 'typescriptreact'],
        \ ['deno'], ['lsp'])
  call s:AddLspServerIfExecutable(l:servers, 'clangd',
        \ ['c', 'cpp', 'objc', 'objcpp'],
        \ ['clangd'], ['--background-index'])
  call s:AddLspServerIfExecutable(l:servers, 'yamlls',
        \ ['yaml'],
        \ ['yaml-language-server'], ['--stdio'])
  call s:AddLspServerIfExecutable(l:servers, 'lemminx',
        \ ['xml', 'xsd', 'xsl', 'xslt', 'svg'],
        \ ['lemminx'], [])
  call s:AddLspServerIfExecutable(l:servers, 'vimls',
        \ ['vim'],
        \ ['vim-language-server'], ['--stdio'])
  call s:AddLspServerIfExecutable(l:servers, 'rust-analyzer',
        \ ['rust'],
        \ ['rust-analyzer'], [])
  call s:AddLspServerIfExecutable(l:servers, 'html',
        \ ['html'],
        \ ['vscode-html-language-server', 'vscode-html-languageserver'], ['--stdio'])
  call s:AddLspServerIfExecutable(l:servers, 'bashls',
        \ ['sh', 'bash'],
        \ ['bash-language-server'], ['start'])
  call s:AddLspServerIfExecutable(l:servers, 'taplo',
        \ ['toml'],
        \ ['taplo', 'taplo-lsp'], ['lsp', 'stdio'])
  call s:AddLspServerIfExecutable(l:servers, 'typos-lsp',
        \ ['c', 'cpp', 'gitcommit', 'html', 'javascript', 'javascriptreact',
        \  'markdown', 'python', 'rust', 'sh', 'text', 'toml', 'typescript',
        \  'typescriptreact', 'vim', 'yaml'],
        \ ['typos-lsp'], ['--stdio'])

  let l:mozuku_path = s:MozukuServerPath()
  if !empty(l:mozuku_path)
    call add(l:servers, #{
          \ name: 'mozuku',
          \ filetype: ['markdown', 'text', 'tex', 'plaintex', 'latex'],
          \ path: l:mozuku_path,
          \ languageId: function('s:MozukuLanguageId'),
          \ initializationOptions: s:MozukuInitOptions(),
          \ })
  endif

  if !empty(l:servers)
    call LspAddServer(l:servers)
  endif
endfunction
