vim9script

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

def RegisterDenols(servers: list<dict<any>>)
  var opts = {
    rootSearch: ['deno.json', 'deno.jsonc', 'deps.ts', 'deps.js', 'import_map.json'],
    runIfSearch: ['deno.json', 'deno.jsonc', 'deps.ts', 'deps.js', 'import_map.json'],
    initializationOptions: {
      enable: v:true,
      lint: v:true,
    },
    workspaceConfig: g:LspDenolsWorkspaceConfig(),
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
    workspaceConfig: g:LspVtslsWorkspaceConfig(),
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
    workspaceConfig: g:LspGoplsWorkspaceConfig(),
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
    workspaceConfig: g:LspJsonlsWorkspaceConfig(),
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
    workspaceConfig: g:LspHarperWorkspaceConfig(),
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
  var mozukuPath = g:LspMozukuServerPath()
  if empty(mozukuPath)
    return
  endif

  var server = {
    name: 'mozuku',
    filetype: ['markdown', 'text', 'tex', 'plaintex', 'latex'],
    omnicompl: v:false,
    path: mozukuPath,
    languageId: function('g:LspMozukuLanguageId'),
    initializationOptions: g:LspMozukuInitOptions(),
  }
  add(servers, server)
enddef

def g:RegisterLspServers()
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
