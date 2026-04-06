vim9script

def AutoMkdir(dir: string, force: bool)
  if isdirectory(dir)
    return
  endif
  if !force && input($'"{dir}" does not exist. Create? [y/N]') !~? '^y\%[es]$'
    return
  endif
  mkdir(iconv(dir, &encoding, &termencoding), 'p')
enddef

augroup vimrc_auto_mkdir
  autocmd!
  autocmd BufWritePre * call AutoMkdir(expand('<afile>:p:h'), !!v:cmdbang)
augroup END

augroup encrypted
  autocmd!
  autocmd BufReadPre,FileReadPre *.gpg set viminfo=
  autocmd BufReadPre,FileReadPre *.gpg set noswapfile
  autocmd BufReadPre,FileReadPre *.gpg set noundofile
  autocmd BufReadPre,FileReadPre *.gpg set bin
  autocmd BufReadPre,FileReadPre *.gpg let b:gpg_cmdheight_save = &cmdheight | set cmdheight=2
  autocmd BufReadPost,FileReadPost *.gpg '[,']!gpg --decrypt 2> /dev/null
  autocmd BufReadPost,FileReadPost *.gpg set nobin
  autocmd BufReadPost,FileReadPost *.gpg let &cmdheight = get(b:, 'gpg_cmdheight_save', &cmdheight) | unlet! b:gpg_cmdheight_save
  autocmd BufReadPost,FileReadPost *.gpg execute ':doautocmd BufReadPost ' .. expand('%:r')
  autocmd BufWritePre,FileWritePre *.gpg '[,']!gpg --default-recipient-self -ae 2>/dev/null
  autocmd BufWritePost,FileWritePost *.gpg undo
augroup END
