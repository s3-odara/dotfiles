vim9script

if exists('g:loaded_gitsign_vim9')
  finish
endif
g:loaded_gitsign_vim9 = 1

const SIGN_GROUP = 'gitsign'
const SIGN_PRIORITY = 10
const SIGN_ADD = 'GitSignAdd'
const SIGN_CHANGE = 'GitSignChange'
const SIGN_DELETE = 'GitSignDelete'
const SIGN_DELETE_FIRST = 'GitSignDeleteFirstLine'

highlight default link GitSignAddHL DiffAdd
highlight default link GitSignChangeHL DiffChange
highlight default link GitSignDeleteHL DiffDelete

execute $'sign define {SIGN_ADD} text=+ texthl=GitSignAddHL'
execute $'sign define {SIGN_CHANGE} text=! texthl=GitSignChangeHL'
execute $'sign define {SIGN_DELETE} text=_ texthl=GitSignDeleteHL'
execute $'sign define {SIGN_DELETE_FIRST} text=^ texthl=GitSignDeleteHL'

def Escape(path: string): string
  return shellescape(path)
enddef

def Run(cmd: string): list<string>
  return systemlist(cmd)
enddef

def ClearSigns(buf: number)
  sign_unplace(SIGN_GROUP, {buffer: buf})
enddef

def ParseHunk(line: string): list<number>
  var m = matchlist(line, '^@@ -\(\d\+\)\%(,\(\d*\)\)\? +\(\d\+\)\%(,\(\d*\)\)\? @@')
  if empty(m)
    return []
  endif
  return [
    str2nr(m[1]),
    empty(m[2]) ? 1 : str2nr(m[2]),
    str2nr(m[3]),
    empty(m[4]) ? 1 : str2nr(m[4]),
  ]
enddef

def Place(buf: number, id: number, lnum: number, name: string)
  sign_place(id, SIGN_GROUP, name, buf, {lnum: lnum, priority: SIGN_PRIORITY})
enddef

def GitRoot(filedir: string): string
  var out = Run('git -C ' .. Escape(filedir) .. ' rev-parse --show-toplevel 2>/dev/null')
  return v:shell_error == 0 && !empty(out) ? out[0] : ''
enddef

def RepoPath(root: string, file: string): string
  var out = Run('git -C ' .. Escape(root) .. ' ls-files --full-name -- ' .. Escape(file) .. ' 2>/dev/null')
  if v:shell_error == 0 && !empty(out)
    return out[0]
  endif
  return substitute(file, '^' .. escape(root .. '/', '\'), '', '')
enddef

def DiffSaved(root: string, relpath: string): list<string>
  return Run('git -C ' .. Escape(root) .. ' diff --no-color --no-ext-diff -U0 -- ' .. Escape(relpath) .. ' 2>/dev/null')
enddef

def DiffModified(root: string, relpath: string, bufnr: number): list<string>
  var basefile = tempname()
  var curfile = tempname()

  var base = systemlist('git -C ' .. Escape(root) .. ' show ' .. Escape('HEAD:' .. relpath) .. ' 2>/dev/null')
  if v:shell_error == 0
    writefile(base, basefile)
  else
    writefile([], basefile)
  endif

  writefile(getbufline(bufnr, 1, '$'), curfile)
  var diff = Run('diff -U0 ' .. Escape(basefile) .. ' ' .. Escape(curfile) .. ' 2>/dev/null')

  delete(basefile)
  delete(curfile)
  return diff
enddef

def g:GitSignUpdate(buf: number = bufnr('%'))
  if !bufexists(buf) || getbufvar(buf, '&buftype') !=# '' || getbufvar(buf, '&diff')
    return
  endif

  var file = bufname(buf)
  if empty(file)
    return
  endif

  file = fnamemodify(file, ':p')
  if !filereadable(file)
    ClearSigns(buf)
    return
  endif

  var root = GitRoot(fnamemodify(file, ':h'))
  if empty(root)
    ClearSigns(buf)
    return
  endif

  var relpath = RepoPath(root, file)
  var diff: list<string>
  if getbufvar(buf, '&modified')
    diff = DiffModified(root, relpath, buf)
  else
    diff = DiffSaved(root, relpath)
  endif

  if v:shell_error > 1
    return
  endif

  ClearSigns(buf)

  var id = 1
  for header in diff->copy()->filter((_, v) => v =~# '^@@ ')
    var h = ParseHunk(header)
    if empty(h)
      continue
    endif

    var old_line = h[0]
    var old_count = h[1]
    var new_line = h[2]
    var new_count = h[3]

    if old_count == 0 && new_count > 0
      for offset in range(new_count)
        Place(buf, id, new_line + offset, SIGN_ADD)
        id += 1
      endfor
    elseif old_count > 0 && new_count == 0
      if new_line == 0
        Place(buf, id, 1, SIGN_DELETE_FIRST)
      else
        Place(buf, id, new_line, SIGN_DELETE)
      endif
      id += 1
    else
      for offset in range(new_count)
        Place(buf, id, new_line + offset, SIGN_CHANGE)
        id += 1
      endfor
    endif
  endfor
enddef

command! GitSignRefresh call g:GitSignUpdate()

augroup gitsign_vim9
  autocmd!
  autocmd BufReadPost,BufWritePost,CursorHold,CursorHoldI,TextChanged,TextChangedI * call g:GitSignUpdate(expand('<abuf>')->str2nr())
augroup END
