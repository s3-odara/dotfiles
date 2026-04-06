vim9script

def FcitxRemote(args: list<string>): string
  if !executable('fcitx5-remote')
    return ''
  endif

  var cmd = join(mapnew(copy(args), (_, value) => shellescape(value)), ' ') .. ' 2>/dev/null'
  return trim(system(cmd))
enddef

def FcitxRemoteJob(args: list<string>)
  if !executable('fcitx5-remote')
    return
  endif

  job_start(args, {out_io: 'null', err_io: 'null'})
enddef

def g:ImeActivate(active: bool): number
  FcitxRemoteJob(active ? ['fcitx5-remote', '-o'] : ['fcitx5-remote', '-c'])
  return 0
enddef

def g:ImeStatus(): number
  return FcitxRemote(['fcitx5-remote']) ==# '2' ? 1 : 0
enddef

set imactivatefunc=g:ImeActivate
set imstatusfunc=g:ImeStatus
