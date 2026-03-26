augroup lsp_setup
  autocmd!
  autocmd User LspSetup call LspOptionsSet(#{
        \ autoComplete: v:false,
        \ semanticHighlight: v:true,
        \ snippetSupport: v:true,
        \ vsnipSupport: v:true,
        \ condensedCompletionMenu: v:true,
        \ usePopupInCodeAction: v:true,
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
        \ commaLimitMax: 5,
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

function! s:LtexPlusServerPath() abort
  let l:path = exepath('ltex-ls-plus')
  if !empty(l:path)
    return l:path
  endif

  let l:candidates = [
        \ expand('~/.local/bin/ltex-ls-plus'),
        \ expand('~/.local/share/ltex-ls-plus/bin/ltex-ls-plus'),
        \ expand('~/.local/opt/ltex-ls-plus/bin/ltex-ls-plus'),
        \ ]
  for l:candidate in l:candidates
    if executable(l:candidate)
      return l:candidate
    endif
  endfor

  return ''
endfunction

function! s:LtexPlusWorkspaceConfig() abort
  let l:enabled = get(g:, 'ltex_plus_enabled', ['gitcommit', 'markdown', 'text'])
  let l:language = get(g:, 'ltex_plus_language', 'en-US')
  let l:disabled_rules = get(g:, 'ltex_plus_disabled_rules', {})

  if !has_key(l:disabled_rules, l:language)
    let l:spelling_rule = 'MORFOLOGIK_RULE_' .. substitute(l:language, '-', '_', 'g')
    let l:disabled_rules = extend(copy(l:disabled_rules), #{}, 'keep')
    let l:disabled_rules[l:language] = [l:spelling_rule]
  endif

  return #{
        \ ltex: #{
        \   enabled: l:enabled,
        \   language: l:language,
        \   diagnosticSeverity: get(g:, 'ltex_plus_diagnostic_severity', 'information'),
        \   completionEnabled: get(g:, 'ltex_plus_completion_enabled', v:true),
        \   additionalRules: #{
        \     enablePickyRules: get(g:, 'ltex_plus_enable_picky_rules', v:false),
        \     motherTongue: get(g:, 'ltex_plus_mother_tongue', 'ja-JP'),
        \   },
        \   dictionary: get(g:, 'ltex_plus_dictionary', {}),
        \   disabledRules: l:disabled_rules,
        \   hiddenFalsePositives: get(g:, 'ltex_plus_hidden_false_positives', {}),
        \   languageToolHttpServerUri: get(g:, 'ltex_plus_language_tool_http_server_uri', ''),
        \ },
        \ }
endfunction

function! s:KakehashiServerPath() abort
  let l:path = exepath('kakehashi')
  if !empty(l:path)
    return l:path
  endif

  let l:local_path = expand('~/.local/bin/kakehashi')
  if executable(l:local_path)
    return l:local_path
  endif

  return ''
endfunction

function! s:AddKakehashiBridgeServer(servers, name, executable_names, args, languages) abort
  let l:executable_name = s:FirstExecutable(a:executable_names)
  if empty(l:executable_name)
    return
  endif

  let a:servers[a:name] = #{
        \ cmd: [exepath(l:executable_name)] + a:args,
        \ languages: a:languages,
        \ }
endfunction

function! s:KakehashiBridgeLanguageServers() abort
  let l:servers = #{}

  call s:AddKakehashiBridgeServer(l:servers, 'denols',
        \ ['deno'], ['lsp'],
        \ ['javascript', 'javascriptreact', 'typescript', 'typescriptreact'])
  call s:AddKakehashiBridgeServer(l:servers, 'vtsls',
        \ ['vtsls'], ['--stdio'],
        \ ['javascript', 'javascriptreact', 'typescript', 'typescriptreact'])
  call s:AddKakehashiBridgeServer(l:servers, 'clangd',
        \ ['clangd'], ['--background-index', '--clang-tidy'],
        \ ['c', 'cpp', 'objc', 'objcpp'])
  call s:AddKakehashiBridgeServer(l:servers, 'gopls',
        \ ['gopls'], [],
        \ ['go', 'gomod', 'gowork', 'gotmpl'])
  call s:AddKakehashiBridgeServer(l:servers, 'yamlls',
        \ ['yaml-language-server'], ['--stdio'],
        \ ['yaml'])
  call s:AddKakehashiBridgeServer(l:servers, 'lemminx',
        \ ['lemminx'], [],
        \ ['xml', 'xsd', 'xsl', 'xslt', 'svg', 'xhtml'])
  call s:AddKakehashiBridgeServer(l:servers, 'vimls',
        \ ['vim-language-server'], ['--stdio'],
        \ ['vim'])
  call s:AddKakehashiBridgeServer(l:servers, 'lua_ls',
        \ ['lua-language-server', 'lua_ls'], [],
        \ ['lua'])
  call s:AddKakehashiBridgeServer(l:servers, 'rust-analyzer',
        \ ['rust-analyzer'], [],
        \ ['rust'])
  call s:AddKakehashiBridgeServer(l:servers, 'html',
        \ ['vscode-html-language-server', 'vscode-html-languageserver'], ['--stdio'],
        \ ['html'])
  call s:AddKakehashiBridgeServer(l:servers, 'bashls',
        \ ['bash-language-server'], ['start'],
        \ ['bash', 'sh'])
  call s:AddKakehashiBridgeServer(l:servers, 'ty',
        \ ['ty'], ['server'],
        \ ['python'])
  call s:AddKakehashiBridgeServer(l:servers, 'taplo',
        \ ['taplo', 'taplo-lsp'], ['lsp', 'stdio'],
        \ ['toml'])

  return extend(l:servers, get(g:, 'kakehashi_bridge_language_servers', {}), 'force')
endfunction

function! s:KakehashiBridgeLanguages() abort
  return get(g:, 'kakehashi_bridge_languages', #{
        \ markdown: #{
        \   bridge: v:null,
        \   },
        \ })
endfunction

function! s:KakehashiInitOptions() abort
  let l:defaults = #{
        \ autoInstall: get(g:, 'kakehashi_auto_install', v:true),
        \ }
  let l:bridge_language_servers = s:KakehashiBridgeLanguageServers()
  let l:bridge_languages = s:KakehashiBridgeLanguages()

  if !empty(l:bridge_language_servers)
    let l:defaults.languageServers = l:bridge_language_servers
  endif
  if !empty(l:bridge_languages)
    let l:defaults.languages = l:bridge_languages
  endif

  let l:user_options = get(g:, 'kakehashi_init_options', {})
  return extend(l:defaults, l:user_options, 'force')
endfunction

function! s:FirstExecutable(candidates) abort
  for l:candidate in a:candidates
    if executable(l:candidate)
      return l:candidate
    endif
  endfor

  return ''
endfunction

function! s:AddLspServerIfExecutable(servers, name, filetypes, executable_names, args, ...) abort
  let l:executable_name = s:FirstExecutable(a:executable_names)
  if !empty(l:executable_name)
    let l:server = #{
          \ name: a:name,
          \ filetype: a:filetypes,
          \ path: exepath(l:executable_name),
          \ args: a:args,
          \ }
    if a:0 >= 1 && type(a:1) == v:t_dict
      call extend(l:server, a:1, 'force')
    endif
    call add(a:servers, l:server)
  endif
endfunction

function! s:RegisterLspServers() abort
  let l:servers = []
  let l:kakehashi_path = s:KakehashiServerPath()

  if !empty(l:kakehashi_path)
    call add(l:servers, #{
          \ name: 'kakehashi',
          \ filetype: get(g:, 'kakehashi_filetypes', [
          \   'bash', 'c', 'cpp', 'css', 'gitcommit', 'go', 'gomod', 'gowork',
          \   'gotmpl', 'html', 'javascript', 'javascriptreact', 'json',
          \   'jsonc', 'latex', 'lua', 'markdown', 'plaintex', 'python',
          \   'rust', 'sh', 'sql', 'text', 'toml', 'tex', 'typescript',
          \   'typescriptreact', 'vim', 'xml', 'yaml',
          \ ]),
          \ path: l:kakehashi_path,
          \ initializationOptions: s:KakehashiInitOptions(),
          \ features: #{
          \   callHierarchy: v:false,
          \   codeAction: v:false,
          \   codeLens: v:false,
          \   completion: v:false,
          \   declaration: v:false,
          \   definition: v:false,
          \   diagnostics: v:false,
          \   documentFormatting: v:false,
          \   documentHighlight: v:false,
          \   documentSymbol: v:false,
          \   foldingRange: v:false,
          \   hover: v:false,
          \   implementation: v:false,
          \   inlayHint: v:false,
          \   references: v:false,
          \   rename: v:false,
          \   selectionRange: v:true,
          \   semanticTokens: v:true,
          \   signatureHelp: v:false,
          \   typeDefinition: v:false,
          \   typeHierarchy: v:false,
          \   workspaceSymbol: v:false,
          \ },
          \ })
  endif

  call s:AddLspServerIfExecutable(l:servers, 'denols',
        \ ['javascript', 'javascriptreact', 'typescript', 'typescriptreact'],
        \ ['deno'], ['lsp'],
        \ #{
        \   rootSearch: ['deno.json', 'deno.jsonc', 'deps.ts', 'deps.js', 'import_map.json'],
        \   runIfSearch: ['deno.json', 'deno.jsonc', 'deps.ts', 'deps.js', 'import_map.json'],
        \   initializationOptions: #{
        \     enable: v:true,
        \     lint: v:true,
        \   },
        \   workspaceConfig: #{
        \     deno: #{
        \       enable: v:true,
        \       lint: v:true,
        \       unstable: v:true,
        \       codeLens: #{
        \         implementations: v:true,
        \         references: v:true,
        \         referencesAllFunctions: v:true,
        \         test: v:true,
        \         testArgs: ['--allow-all'],
        \       },
        \       suggest: #{
        \         autoImports: v:true,
        \         completeFunctionCalls: v:true,
        \         names: v:true,
        \         paths: v:true,
        \         imports: #{
        \           autoDiscover: v:false,
        \           hosts: {
        \             'https://deno.land/': v:true,
        \             'https://jsr.io/': v:true,
        \           },
        \         },
        \       },
        \     },
        \     typescript: #{
        \       inlayHints: #{
        \         parameterNames: #{
        \           enabled: 'all',
        \           suppressWhenArgumentMatchesName: v:true,
        \         },
        \         parameterTypes: #{enabled: v:true},
        \         variableTypes: #{
        \           enabled: v:true,
        \           suppressWhenTypeMatchesName: v:true,
        \         },
        \         propertyDeclarationTypes: #{enabled: v:true},
        \         functionLikeReturnTypes: #{enabled: v:true},
        \         enumMemberValues: #{enabled: v:true},
        \       },
        \     },
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'vtsls',
        \ ['javascript', 'javascriptreact', 'typescript', 'typescriptreact'],
        \ ['vtsls'], ['--stdio'],
        \ #{
        \   rootSearch: ['package.json', 'tsconfig.json', 'jsconfig.json'],
        \   runUnlessSearch: ['deno.json', 'deno.jsonc', 'deps.ts', 'deps.js', 'import_map.json'],
        \   workspaceConfig: #{
        \     vtsls: #{
        \       autoUseWorkspaceTsdk: v:true,
        \     },
        \     typescript: #{
        \       preferGoToSourceDefinition: v:true,
        \       updateImportsOnFileMove: #{enabled: 'always'},
        \       workspaceSymbols: #{scope: 'currentProject'},
        \       suggest: #{completeFunctionCalls: v:true},
        \       preferences: #{preferTypeOnlyAutoImports: v:true},
        \     },
        \     javascript: #{
        \       updateImportsOnFileMove: #{enabled: 'always'},
        \       suggest: #{completeFunctionCalls: v:true},
        \       inlayHints: #{
        \         parameterNames: #{
        \           enabled: 'all',
        \           suppressWhenArgumentMatchesName: v:true,
        \         },
        \         parameterTypes: #{enabled: v:true},
        \         variableTypes: #{
        \           enabled: v:true,
        \           suppressWhenTypeMatchesName: v:true,
        \         },
        \         propertyDeclarationTypes: #{enabled: v:true},
        \         functionLikeReturnTypes: #{enabled: v:true},
        \         enumMemberValues: #{enabled: v:true},
        \       },
        \     },
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'clangd',
        \ ['c', 'cpp', 'objc', 'objcpp'],
        \ ['clangd'], ['--background-index', '--clang-tidy'],
        \ #{rootSearch: ['compile_commands.json', 'compile_flags.txt', '.clangd', '.git']})
  call s:AddLspServerIfExecutable(l:servers, 'gopls',
        \ ['go', 'gomod', 'gowork', 'gotmpl'],
        \ ['gopls'], [],
        \ #{
        \   rootSearch: ['go.work', 'go.mod', '.git'],
        \   workspaceConfig: #{
        \     gopls: #{
        \       completeUnimported: v:true,
        \       usePlaceholders: v:true,
        \       staticcheck: v:true,
        \       gofumpt: v:true,
        \       matcher: 'Fuzzy',
        \       hints: #{
        \         assignVariableTypes: v:true,
        \         compositeLiteralFields: v:true,
        \         compositeLiteralTypes: v:true,
        \         constantValues: v:true,
        \         functionTypeParameters: v:true,
        \         ignoredError: v:true,
        \         parameterNames: v:true,
        \         rangeVariableTypes: v:true,
        \       },
        \       codelenses: #{
        \         generate: v:true,
        \         run_govulncheck: v:true,
        \         tidy: v:true,
        \         upgrade_dependency: v:true,
        \         vendor: v:true,
        \       },
        \     },
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'yamlls',
        \ ['yaml'],
        \ ['yaml-language-server'], ['--stdio'],
        \ #{
        \   workspaceConfig: #{
        \     yaml: #{
        \       validate: v:true,
        \       hover: v:true,
        \       completion: v:true,
        \       format: #{enable: v:true},
        \       schemaStore: #{enable: v:true},
        \     },
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'lemminx',
        \ ['xml', 'xsd', 'xsl', 'xslt', 'svg', 'xhtml'],
        \ ['lemminx'], [],
        \ #{
        \   workspaceConfig: #{
        \     xml: #{
        \       codeLens: #{enabled: v:true},
        \       downloadExternalResources: #{enabled: v:true},
        \       validation: #{
        \         enabled: v:true,
        \         namespaces: #{enabled: 'always'},
        \         schema: #{enabled: 'always'},
        \       },
        \     },
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'vimls',
        \ ['vim'],
        \ ['vim-language-server'], ['--stdio'],
        \ #{
        \   initializationOptions: #{
        \     isNeovim: has('nvim'),
        \     iskeyword: &iskeyword,
        \     runtimepath: &runtimepath,
        \     diagnostic: #{enable: v:true},
        \     indexes: #{runtimepath: v:true},
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'lua_ls',
        \ ['lua'],
        \ ['lua-language-server', 'lua_ls'], [],
        \ #{
        \   workspaceConfig: #{
        \     Lua: #{
        \       completion: #{
        \         autoRequire: v:true,
        \         callSnippet: 'Both',
        \       },
        \       hint: #{enable: v:true},
        \       runtime: #{version: 'LuaJIT'},
        \       diagnostics: #{globals: ['vim']},
        \       workspace: #{checkThirdParty: v:false},
        \       telemetry: #{enable: v:false},
        \     },
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'rust-analyzer',
        \ ['rust'],
        \ ['rust-analyzer'], [],
        \ #{
        \   rootSearch: ['Cargo.toml', 'rust-project.json', '.git'],
        \   initializationOptions: #{
        \     inlayHints: #{
        \       typeHints: #{enable: v:true},
        \       parameterHints: #{enable: v:true},
        \     },
        \   },
        \   workspaceConfig: {
        \     'rust-analyzer': #{
        \       check: #{command: 'clippy'},
        \       cargo: #{buildScripts: #{enable: v:true}},
        \       procMacro: #{enable: v:true},
        \       completion: #{autoimport: #{enable: v:true}},
        \     },
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'html',
        \ ['html'],
        \ ['vscode-html-language-server', 'vscode-html-languageserver'], ['--stdio'],
        \ #{
        \   workspaceConfig: #{
        \     html: #{
        \       hover: #{
        \         documentation: v:true,
        \         references: v:true,
        \       },
        \       validate: #{
        \         scripts: v:true,
        \         styles: v:true,
        \       },
        \       format: #{
        \         enable: v:true,
        \         wrapLineLength: 120,
        \       },
        \     },
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'bashls',
        \ ['sh', 'bash'],
        \ ['bash-language-server'], ['start'],
        \ #{
        \   workspaceConfig: #{
        \     bashIde: #{
        \       shellcheckPath: exepath('shellcheck'),
        \       shellcheckExternalSources: v:true,
        \       shfmt: #{
        \         path: exepath('shfmt'),
        \         languageDialect: 'auto',
        \         simplifyCode: v:true,
        \       },
        \     },
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'ty',
        \ ['python'],
        \ ['ty'], ['server'],
        \ #{
        \   rootSearch: ['pyproject.toml', 'setup.py', 'setup.cfg',
        \                'requirements.txt', '.git'],
        \   features: #{
        \     codeAction: v:false,
        \     documentFormatting: v:false,
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'ruff',
        \ ['python'],
        \ ['ruff'], ['server'],
        \ #{
        \   rootSearch: ['pyrightconfig.json', 'pyproject.toml', 'ruff.toml',
        \                '.ruff.toml', 'setup.py', 'setup.cfg',
        \                'requirements.txt', '.git'],
        \   features: #{
        \     completion: v:false,
        \     hover: v:false,
        \     references: v:false,
        \     rename: v:false,
        \     documentSymbol: v:false,
        \     semanticTokens: v:false,
        \     signatureHelp: v:false,
        \   },
        \ })
  call s:AddLspServerIfExecutable(l:servers, 'taplo',
        \ ['toml'],
        \ ['taplo', 'taplo-lsp'], ['lsp', 'stdio'])
  call s:AddLspServerIfExecutable(l:servers, 'harper-ls',
        \ ['gitcommit', 'markdown', 'text'],
        \ ['harper-ls'], ['--stdio'],
        \ #{
        \   workspaceConfig: {
        \     'harper-ls': {
        \       'diagnosticSeverity': 'information',
        \       'dialect': 'American',
        \       'isolateEnglish': v:false,
        \       'maxFileLength': 120000,
        \       'excludePatterns': [],
        \       'codeActions': {
        \         'ForceStable': v:true,
        \       },
        \       'markdown': {
        \         'IgnoreLinkTitle': v:true,
        \       },
        \       'linters': {
        \         'SpellCheck': v:false,
        \         'SentenceCapitalization': v:false,
        \         'AnA': v:true,
        \         'UnclosedQuotes': v:true,
        \         'WrongQuotes': v:false,
        \         'LongSentences': v:false,
        \         'RepeatedWords': v:true,
        \         'Spaces': v:true,
        \         'Matcher': v:true,
        \         'CorrectNumberSuffix': v:true,
        \         'SpelledNumbers': v:false,
        \       },
        \     },
        \   },
        \ })
  let l:ltex_plus_path = s:LtexPlusServerPath()
  if !empty(l:ltex_plus_path)
    call add(l:servers, #{
          \ name: 'ltex-ls-plus',
          \ filetype: ['gitcommit', 'markdown', 'text'],
          \ path: l:ltex_plus_path,
          \ workspaceConfig: s:LtexPlusWorkspaceConfig(),
          \ })
  endif
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
