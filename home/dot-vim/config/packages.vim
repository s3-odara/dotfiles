vim9script
scriptencoding utf-8

const MINPAC_DIR = expand('~/.vim/pack/minpac/opt/minpac')
const MINPAC_REV = '7a616ad2393139dbdf7514c14606098404e38625'

def EnsureMinpacInstalled()
  if isdirectory(MINPAC_DIR)
    return
  endif

  system(['git', 'clone', 'https://github.com/k-takata/minpac', MINPAC_DIR])
  system(['git', '-C', MINPAC_DIR, 'checkout', MINPAC_REV])
  packadd minpac
enddef

def g:PackInit()
  packadd minpac
  minpac#init()

  minpac#add('https://github.com/k-takata/minpac.git', {
    type: 'opt',
    rev: MINPAC_REV,
  })

  # UI / Tools
  minpac#add('https://github.com/vim-fuzzbox/fuzzbox.vim.git', {
    rev: 'f62cd85043975b189d32db8b07bd7b05e63a7cff',
  })
  minpac#add('https://github.com/mattn/emmet-vim.git', {
    rev: '92ef2f74f4093edc99db5e9e4cf7e40116a85bd6',
  })
  minpac#add('https://github.com/alvan/vim-closetag.git', {
    rev: 'd0a562f8bdb107a50595aefe53b1a690460c3822',
  })
  minpac#add('https://github.com/itchyny/vim-gitbranch.git', {
    rev: '1a8ba866f3eaf0194783b9f8573339d6ede8f1ed',
  })
  minpac#add('https://github.com/mao-yining/undotree.vim', {
    rev: 'c103f3c2e2eb8df4b811b045b8ed626f968f0138',
  })
  minpac#add('https://github.com/girishji/easyjump.vim.git', {
    rev: '7be7e1b6e8000971d0f6ef9e8480f86094f56635',
  })
  minpac#add('https://github.com/madox2/vim-ai.git', {
    type: 'opt',
    rev: 'f46c2343a7d81c74ab249214ed9d0a9c6edac07f',
  })

  # LSP / Completion
  minpac#add('https://github.com/yegappan/lsp.git', {
    rev: '989016ae2ae4cbf304a9ca29478f47fec794493f',
  })

  # Snippet
  minpac#add('https://github.com/hrsh7th/vim-vsnip.git', {
    rev: '9bcfabea653abdcdac584283b5097c3f8760abaa',
  })
  minpac#add('https://github.com/hrsh7th/vim-vsnip-integ.git', {
    rev: 'c7c93934dece8315db3649bdc6898b76358a8b8d',
  })
enddef

EnsureMinpacInstalled()

command! -bar PackUpdate call g:PackInit() | call minpac#update()
command! -bar PackClean  call g:PackInit() | call minpac#clean()
command! -bar PackStatus packadd minpac | call minpac#status()
