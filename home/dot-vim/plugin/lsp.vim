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

def g:LspPluginApplyLspOptions()
  ApplyLspOptions()
enddef

augroup lsp_setup
  autocmd!
  autocmd User LspSetup call g:LspPluginApplyLspOptions()
  autocmd User LspSetup call g:LspPluginRegisterLspServers()
augroup END

def MozukuServerPath(): string
  var path = exepath('mozuku-lsp')
  if !empty(path)
    return path
  endif

  var localPath = expand('~/.local/bin/mozuku-lsp')
  if executable(localPath)
    return localPath
  endif

  return ''
enddef

def MozukuLanguageId(): string
  if &filetype ==# 'text'
    return 'japanese'
  endif
  if &filetype ==# 'tex' || &filetype ==# 'plaintex'
    return 'latex'
  endif
  return &filetype
enddef

def g:LspMozukuLanguageId(): string
  return MozukuLanguageId()
enddef

def MozukuInitOptions(): dict<any>
  var warnings = get(g:, 'mozuku_warnings', {})
  var rules = get(g:, 'mozuku_rules', {})
  var defaultDicdir = isdirectory(expand('~/.local/lib/mecab/dic/ipadic'))
    ? expand('~/.local/lib/mecab/dic/ipadic')
    : ''

  var warningDefaults = {
    particleDuplicate: v:true,
    particleSequence: v:true,
    particleMismatch: v:true,
    sentenceStructure: v:false,
    styleConsistency: v:false,
    redundancy: v:false,
  }
  extend(warningDefaults, warnings, 'force')

  var ruleDefaults = {
    commaLimit: v:true,
    adversativeGa: v:true,
    duplicateParticleSurface: v:true,
    adjacentParticles: v:true,
    conjunctionRepeat: v:true,
    raDropping: v:true,
    commaLimitMax: 5,
    adversativeGaMax: 1,
    duplicateParticleSurfaceMaxRepeat: 1,
    adjacentParticlesMaxRepeat: 1,
    conjunctionRepeatMax: 1,
  }
  extend(ruleDefaults, rules, 'force')

  return {
    mozuku: {
      mecab: {
        dicdir: get(g:, 'mozuku_mecab_dicdir', defaultDicdir),
        charset: get(g:, 'mozuku_mecab_charset', 'UTF-8'),
      },
      analysis: {
        enableCaboCha: get(g:, 'mozuku_analysis_enable_cabocha', executable('cabocha') ? v:true : v:false),
        grammarCheck: get(g:, 'mozuku_analysis_grammar_check', v:true),
        minJapaneseRatio: get(g:, 'mozuku_analysis_min_japanese_ratio', 0.1),
        warningMinSeverity: get(g:, 'mozuku_analysis_warning_min_severity', 2),
        warnings: warningDefaults,
        rules: ruleDefaults,
      },
    },
  }
enddef

def KakehashiBridgeLanguages(): dict<any>
  return get(g:, 'kakehashi_bridge_languages', {
    markdown: {
      bridge: v:null,
    },
  })
enddef

def FirstExecutable(candidates: list<string>): string
  for candidate in candidates
    if executable(candidate)
      return candidate
    endif
  endfor

  return ''
enddef

def AddLspServerIfExecutable(
  servers: list<dict<any>>,
  name: string,
  filetypes: list<string>,
  executableNames: list<string>,
  args: list<string>,
  ...rest: list<any>
)
  var executableName = FirstExecutable(executableNames)
  if empty(executableName)
    return
  endif

  var server = {
    name: name,
    filetype: filetypes,
    path: exepath(executableName),
    args: args,
  }

  if !empty(rest) && type(rest[0]) == v:t_dict
    extend(server, rest[0], 'force')
  endif

  add(servers, server)
enddef

def TypescriptInlayHints(): dict<any>
  return {
    parameterNames: {
      enabled: 'all',
      suppressWhenArgumentMatchesName: v:true,
    },
    parameterTypes: {enabled: v:true},
    variableTypes: {
      enabled: v:true,
      suppressWhenTypeMatchesName: v:true,
    },
    propertyDeclarationTypes: {enabled: v:true},
    functionLikeReturnTypes: {enabled: v:true},
    enumMemberValues: {enabled: v:true},
  }
enddef

def DenolsWorkspaceConfig(): dict<any>
  return {
    deno: {
      enable: v:true,
      lint: v:true,
      unstable: v:true,
      codeLens: {
        implementations: v:true,
        references: v:true,
        referencesAllFunctions: v:true,
        test: v:true,
        testArgs: ['--allow-all'],
      },
      suggest: {
        autoImports: v:true,
        completeFunctionCalls: v:true,
        names: v:true,
        paths: v:true,
        imports: {
          autoDiscover: v:false,
          hosts: {
            'https://deno.land/': v:true,
            'https://jsr.io/': v:true,
          },
        },
      },
    },
    typescript: {
      inlayHints: TypescriptInlayHints(),
    },
  }
enddef

def VtslsWorkspaceConfig(): dict<any>
  return {
    vtsls: {
      autoUseWorkspaceTsdk: v:true,
    },
    typescript: {
      preferGoToSourceDefinition: v:true,
      updateImportsOnFileMove: {enabled: 'always'},
      workspaceSymbols: {scope: 'currentProject'},
      suggest: {completeFunctionCalls: v:true},
      preferences: {preferTypeOnlyAutoImports: v:true},
    },
    javascript: {
      updateImportsOnFileMove: {enabled: 'always'},
      suggest: {completeFunctionCalls: v:true},
      inlayHints: TypescriptInlayHints(),
    },
  }
enddef

def GoplsWorkspaceConfig(): dict<any>
  return {
    gopls: {
      completeUnimported: v:true,
      usePlaceholders: v:true,
      staticcheck: v:true,
      gofumpt: v:true,
      matcher: 'Fuzzy',
      hints: {
        assignVariableTypes: v:true,
        compositeLiteralFields: v:true,
        compositeLiteralTypes: v:true,
        constantValues: v:true,
        functionTypeParameters: v:true,
        ignoredError: v:true,
        parameterNames: v:true,
        rangeVariableTypes: v:true,
      },
      codelenses: {
        generate: v:true,
        run_govulncheck: v:true,
        tidy: v:true,
        upgrade_dependency: v:true,
        vendor: v:true,
      },
    },
  }
enddef

def JsonlsWorkspaceConfig(): dict<any>
  return {
    json: {
      validate: {
        enable: v:true,
        comments: 'warning',
        trailingCommas: 'warning',
        schemaValidation: 'warning',
        schemaRequest: 'warning',
      },
      format: {enable: v:true},
      keepLines: {enable: v:false},
      resultLimit: 5000,
      jsonFoldingLimit: 5000,
      jsoncFoldingLimit: 5000,
      schemas: [
        {
          uri: 'https://json.schemastore.org/package.json',
          fileMatch: ['package.json'],
        },
        {
          uri: 'https://json.schemastore.org/tsconfig.json',
          fileMatch: ['tsconfig.json', 'tsconfig.*.json'],
        },
        {
          uri: 'https://json.schemastore.org/jsconfig.json',
          fileMatch: ['jsconfig.json', 'jsconfig.*.json'],
        },
        {
          uri: 'https://json.schemastore.org/deno.json',
          fileMatch: ['deno.json', 'deno.jsonc'],
        },
      ],
    },
  }
enddef

def HarperWorkspaceConfig(): dict<any>
  return {
    'harper-ls': {
      'diagnosticSeverity': 'information',
      'dialect': 'American',
      'isolateEnglish': v:false,
      'maxFileLength': 120000,
      'excludePatterns': [],
      'codeActions': {
        'ForceStable': v:true,
      },
      'markdown': {
        'IgnoreLinkTitle': v:true,
      },
      'linters': {
        'SpellCheck': v:false,
        'SentenceCapitalization': v:false,
        'AnA': v:true,
        'UnclosedQuotes': v:true,
        'WrongQuotes': v:false,
        'LongSentences': v:false,
        'RepeatedWords': v:true,
        'Spaces': v:true,
        'Matcher': v:true,
        'CorrectNumberSuffix': v:true,
        'SpelledNumbers': v:false,
      },
    },
  }
enddef

def RegisterDenols(servers: list<dict<any>>)
  var opts = {
    rootSearch: ['deno.json', 'deno.jsonc', 'deps.ts', 'deps.js', 'import_map.json'],
    runIfSearch: ['deno.json', 'deno.jsonc', 'deps.ts', 'deps.js', 'import_map.json'],
    initializationOptions: {
      enable: v:true,
      lint: v:true,
    },
    workspaceConfig: DenolsWorkspaceConfig(),
  }
  AddLspServerIfExecutable(
    servers,
    'denols',
    ['javascript', 'javascriptreact', 'typescript', 'typescriptreact'],
    ['deno'],
    ['lsp'],
    opts
  )
enddef

def RegisterVtsls(servers: list<dict<any>>)
  var opts = {
    rootSearch: ['package.json', 'tsconfig.json', 'jsconfig.json'],
    runUnlessSearch: ['deno.json', 'deno.jsonc', 'deps.ts', 'deps.js', 'import_map.json'],
    workspaceConfig: VtslsWorkspaceConfig(),
  }
  AddLspServerIfExecutable(
    servers,
    'vtsls',
    ['javascript', 'javascriptreact', 'typescript', 'typescriptreact'],
    ['vtsls'],
    ['--stdio'],
    opts
  )
enddef

def RegisterClangd(servers: list<dict<any>>)
  var opts = {rootSearch: ['compile_commands.json', 'compile_flags.txt', '.clangd', '.git']}
  AddLspServerIfExecutable(
    servers,
    'clangd',
    ['c', 'cpp', 'objc', 'objcpp'],
    ['clangd'],
    ['--background-index', '--clang-tidy'],
    opts
  )
enddef

def RegisterGopls(servers: list<dict<any>>)
  var opts = {
    rootSearch: ['go.work', 'go.mod', '.git'],
    workspaceConfig: GoplsWorkspaceConfig(),
  }
  AddLspServerIfExecutable(
    servers,
    'gopls',
    ['go', 'gomod', 'gowork', 'gotmpl'],
    ['gopls'],
    [],
    opts
  )
enddef

def RegisterJsonls(servers: list<dict<any>>)
  var opts = {
    workspaceConfig: JsonlsWorkspaceConfig(),
  }
  AddLspServerIfExecutable(
    servers,
    'jsonls',
    ['json', 'jsonc'],
    ['vscode-json-language-server', 'vscode-json-languageserver'],
    ['--stdio'],
    opts
  )
enddef

def RegisterYamlls(servers: list<dict<any>>)
  var opts = {
    workspaceConfig: {
      yaml: {
        validate: v:true,
        hover: v:true,
        completion: v:true,
        format: {enable: v:true},
        schemaStore: {enable: v:true},
      },
    },
  }
  AddLspServerIfExecutable(
    servers,
    'yamlls',
    ['yaml'],
    ['yaml-language-server'],
    ['--stdio'],
    opts
  )
enddef

def RegisterLemminx(servers: list<dict<any>>)
  var opts = {
    workspaceConfig: {
      xml: {
        codeLens: {enabled: v:true},
        downloadExternalResources: {enabled: v:true},
        validation: {
          enabled: v:true,
          namespaces: {enabled: 'always'},
          schema: {enabled: 'always'},
        },
      },
    },
  }
  AddLspServerIfExecutable(
    servers,
    'lemminx',
    ['xml', 'xsd', 'xsl', 'xslt', 'svg', 'xhtml'],
    ['lemminx'],
    [],
    opts
  )
enddef

def RegisterVimls(servers: list<dict<any>>)
  var opts = {
    initializationOptions: {
      isNeovim: has('nvim'),
      iskeyword: &iskeyword,
      runtimepath: &runtimepath,
      diagnostic: {enable: v:true},
      indexes: {runtimepath: v:true},
    },
  }
  AddLspServerIfExecutable(
    servers,
    'vimls',
    ['vim'],
    ['vim-language-server'],
    ['--stdio'],
    opts
  )
enddef

def RegisterLuaLs(servers: list<dict<any>>)
  var opts = {
    workspaceConfig: {
      Lua: {
        completion: {
          autoRequire: v:true,
          callSnippet: 'Both',
        },
        hint: {enable: v:true},
        runtime: {version: 'LuaJIT'},
        diagnostics: {globals: ['vim']},
        workspace: {checkThirdParty: v:false},
        telemetry: {enable: v:false},
      },
    },
  }
  AddLspServerIfExecutable(
    servers,
    'lua_ls',
    ['lua'],
    ['lua-language-server', 'lua_ls'],
    [],
    opts
  )
enddef

def RegisterRustAnalyzer(servers: list<dict<any>>)
  var opts = {
    rootSearch: ['Cargo.toml', 'rust-project.json', '.git'],
    initializationOptions: {
      inlayHints: {
        typeHints: {enable: v:true},
        parameterHints: {enable: v:true},
      },
    },
    workspaceConfig: {
      'rust-analyzer': {
        check: {command: 'clippy'},
        cargo: {buildScripts: {enable: v:true}},
        procMacro: {enable: v:true},
        completion: {autoimport: {enable: v:true}},
      },
    },
  }
  AddLspServerIfExecutable(
    servers,
    'rust-analyzer',
    ['rust'],
    ['rust-analyzer'],
    [],
    opts
  )
enddef

def RegisterZls(servers: list<dict<any>>)
  var opts = {
    rootSearch: ['zls.json', 'build.zig', 'build.zig.zon', '.git'],
  }
  AddLspServerIfExecutable(
    servers,
    'zls',
    ['zig'],
    ['zls'],
    [],
    opts
  )
enddef

def RegisterHtml(servers: list<dict<any>>)
  var opts = {
    workspaceConfig: {
      html: {
        hover: {
          documentation: v:true,
          references: v:true,
        },
        validate: {
          scripts: v:true,
          styles: v:true,
        },
        format: {
          enable: v:true,
          wrapLineLength: 120,
        },
      },
    },
  }
  AddLspServerIfExecutable(
    servers,
    'html',
    ['html'],
    ['vscode-html-language-server', 'vscode-html-languageserver'],
    ['--stdio'],
    opts
  )
enddef

def RegisterBashls(servers: list<dict<any>>)
  var opts = {
    workspaceConfig: {
      bashIde: {
        shellcheckPath: exepath('shellcheck'),
        shellcheckExternalSources: v:true,
        shfmt: {
          path: exepath('shfmt'),
          languageDialect: 'auto',
          simplifyCode: v:true,
        },
      },
    },
  }
  AddLspServerIfExecutable(
    servers,
    'bashls',
    ['sh', 'bash'],
    ['bash-language-server'],
    ['start'],
    opts
  )
enddef

def RegisterTy(servers: list<dict<any>>)
  var opts = {
    rootSearch: ['pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.git'],
    features: {
      codeAction: v:false,
      documentFormatting: v:false,
    },
  }
  AddLspServerIfExecutable(
    servers,
    'ty',
    ['python'],
    ['ty'],
    ['server'],
    opts
  )
enddef

def RegisterRuff(servers: list<dict<any>>)
  var opts = {
    omnicompl: v:false,
    rootSearch: [
      'pyrightconfig.json',
      'pyproject.toml',
      'ruff.toml',
      '.ruff.toml',
      'setup.py',
      'setup.cfg',
      'requirements.txt',
      '.git',
    ],
    features: {
      completion: v:false,
      hover: v:false,
      references: v:false,
      rename: v:false,
      documentSymbol: v:false,
      semanticTokens: v:false,
      signatureHelp: v:false,
    },
  }
  AddLspServerIfExecutable(
    servers,
    'ruff',
    ['python'],
    ['ruff'],
    ['server'],
    opts
  )
enddef

def RegisterTaplo(servers: list<dict<any>>)
  AddLspServerIfExecutable(
    servers,
    'taplo',
    ['toml'],
    ['taplo', 'taplo-lsp'],
    ['lsp', 'stdio']
  )
enddef

def RegisterHarper(servers: list<dict<any>>)
  var opts = {
    omnicompl: v:false,
    workspaceConfig: HarperWorkspaceConfig(),
  }
  AddLspServerIfExecutable(
    servers,
    'harper-ls',
    ['gitcommit', 'markdown', 'text'],
    ['harper-ls'],
    ['--stdio'],
    opts
  )
enddef

def RegisterTypos(servers: list<dict<any>>)
  var opts = {
    omnicompl: v:false,
  }
  AddLspServerIfExecutable(
    servers,
    'typos-lsp',
    ['c', 'cpp', 'gitcommit', 'html', 'javascript', 'javascriptreact', 'markdown', 'python', 'rust', 'sh', 'text', 'toml', 'typescript', 'typescriptreact', 'vim', 'yaml'],
    ['typos-lsp'],
    ['--stdio'],
    opts
  )
enddef

def RegisterMozuku(servers: list<dict<any>>)
  var mozukuPath = MozukuServerPath()
  if empty(mozukuPath)
    return
  endif

  var server = {
    name: 'mozuku',
    filetype: ['markdown', 'text', 'tex', 'plaintex', 'latex'],
    omnicompl: v:false,
    path: mozukuPath,
    languageId: function('g:LspMozukuLanguageId'),
    initializationOptions: MozukuInitOptions(),
  }
  add(servers, server)
enddef

def RegisterLspServers()
  var servers: list<dict<any>> = []

  RegisterTypos(servers)
  RegisterDenols(servers)
  RegisterVtsls(servers)
  RegisterClangd(servers)
  RegisterGopls(servers)
  RegisterJsonls(servers)
  RegisterYamlls(servers)
  RegisterLemminx(servers)
  RegisterVimls(servers)
  RegisterLuaLs(servers)
  RegisterRustAnalyzer(servers)
  RegisterZls(servers)
  RegisterHtml(servers)
  RegisterBashls(servers)
  RegisterRuff(servers)
  RegisterTy(servers)
  RegisterTaplo(servers)
  RegisterHarper(servers)
  RegisterMozuku(servers)

  if !empty(servers)
    g:LspAddServer(servers)
  endif
enddef

def g:LspPluginRegisterLspServers()
  RegisterLspServers()
enddef
