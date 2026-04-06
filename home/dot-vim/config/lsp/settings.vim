vim9script

def g:LspMozukuServerPath(): string
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

def g:LspMozukuInitOptions(): dict<any>
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

def g:LspDenolsWorkspaceConfig(): dict<any>
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

def g:LspVtslsWorkspaceConfig(): dict<any>
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

def g:LspGoplsWorkspaceConfig(): dict<any>
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

def g:LspJsonlsWorkspaceConfig(): dict<any>
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

def g:LspHarperWorkspaceConfig(): dict<any>
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
