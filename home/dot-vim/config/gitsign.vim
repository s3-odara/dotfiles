vim9script

if !exists('g:gitsign_enable')
  g:gitsign_enable = 1
endif
# The first normal update after idle runs immediately.
# This delay is the quiet period before queued retries run.
if !exists('g:gitsign_cooldown_ms')
  g:gitsign_cooldown_ms = 1000
endif
if !exists('g:gitsign_max_file_lines')
  g:gitsign_max_file_lines = 20000
endif
if !exists('g:gitsign_max_file_bytes')
  g:gitsign_max_file_bytes = 1048576
endif
if !exists('g:gitsign_enable_modified_buffer')
  g:gitsign_enable_modified_buffer = 1
endif

const SIGN_GROUP = 'gitsign'
const SIGN_PRIORITY = 10
const SIGN_ADD = 'GitSignAdd'
const SIGN_CHANGE = 'GitSignChange'
const SIGN_DELETE = 'GitSignDelete'
const SIGN_DELETE_FIRST = 'GitSignDeleteFirstLine'
const MODE_SAVED = 'saved'
const MODE_MODIFIED = 'modified'
const MODE_HEAD = 'head'
const MODE_SHOW = 'show'

highlight default link GitSignAddHL DiffAdd
highlight default link GitSignChangeHL DiffChange
highlight default link GitSignDeleteHL DiffDelete

execute $'sign define {SIGN_ADD} text=+ texthl=GitSignAddHL'
execute $'sign define {SIGN_CHANGE} text=! texthl=GitSignChangeHL'
execute $'sign define {SIGN_DELETE} text=_ texthl=GitSignDeleteHL'
execute $'sign define {SIGN_DELETE_FIRST} text=^ texthl=GitSignDeleteHL'

var state_by_buf: dict<dict<any>> = {}
var root_by_dir: dict<string> = {}
var relpath_by_file: dict<string> = {}
var head_cache: dict<dict<any>> = {}

def EnsureState(buf: number): dict<any>
  var key = string(buf)
  if !has_key(state_by_buf, key)
    state_by_buf[key] = {
      generation: 0,
      timer: -1,
      pending_generation: -1,
      job: v:none,
      job_seq: 0,
      job_mode: '',
      file: '',
      repo_root: '',
      relpath: '',
      last_signs: {},
      next_sign_id: 1,
      tempfiles: [],
    }
  endif
  return state_by_buf[key]
enddef

def BufState(buf: number): dict<any>
  return get(state_by_buf, string(buf), {})
enddef

def AddTempfile(buf: number, path: string)
  if empty(path)
    return
  endif
  var state = EnsureState(buf)
  if index(state.tempfiles, path) < 0
    add(state.tempfiles, path)
  endif
enddef

def DeleteFileIfExists(path: string)
  if empty(path)
    return
  endif
  if filereadable(path)
    delete(path)
  endif
enddef

def DeletePaths(paths: list<string>)
  for path in paths
    DeleteFileIfExists(path)
  endfor
enddef

def CleanupTrackedTempfiles(buf: number)
  var state = BufState(buf)
  if empty(state)
    return
  endif
  DeletePaths(copy(state.tempfiles))
  state.tempfiles = []
enddef

def StopTimer(buf: number)
  var state = BufState(buf)
  if empty(state)
    return
  endif
  if state.timer != -1
    timer_stop(state.timer)
    state.timer = -1
  endif
  state.pending_generation = -1
enddef

def StopJob(buf: number)
  var state = BufState(buf)
  if empty(state)
    return
  endif
  if type(state.job) == v:t_job && job_status(state.job) ==# 'run'
    job_stop(state.job)
  endif
  state.job = v:none
  state.job_mode = ''
enddef

def ClearSigns(buf: number)
  sign_unplace(SIGN_GROUP, {buffer: buf})
  var state = EnsureState(buf)
  state.last_signs = {}
enddef

def ResetBuffer(buf: number)
  StopTimer(buf)
  StopJob(buf)
  CleanupTrackedTempfiles(buf)
  ClearSigns(buf)
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

def ParseDiff(diff: list<string>): list<dict<any>>
  var signs: list<dict<any>> = []
  for header in diff
    if header !~# '^@@ '
      continue
    endif

    var h = ParseHunk(header)
    if empty(h)
      continue
    endif

    var old_count = h[1]
    var new_line = h[2]
    var new_count = h[3]

    if old_count == 0 && new_count > 0
      for offset in range(new_count)
        add(signs, {lnum: new_line + offset, name: SIGN_ADD})
      endfor
    elseif old_count > 0 && new_count == 0
      add(signs, {lnum: new_line == 0 ? 1 : new_line, name: new_line == 0 ? SIGN_DELETE_FIRST : SIGN_DELETE})
    else
      for offset in range(new_count)
        add(signs, {lnum: new_line + offset, name: SIGN_CHANGE})
      endfor
    endif
  endfor
  return signs
enddef

def SignsKey(sign: dict<any>): string
  return string(sign.lnum) .. ':' .. sign.name
enddef

def ApplySigns(buf: number, signs: list<dict<any>>)
  var state = EnsureState(buf)
  var previous = state.last_signs
  var next: dict<dict<any>> = {}

  for sign in signs
    var key = SignsKey(sign)
    if has_key(next, key)
      continue
    endif
    if has_key(previous, key)
      next[key] = previous[key]
      remove(previous, key)
      continue
    endif
    var id = state.next_sign_id
    state.next_sign_id += 1
    sign_place(id, SIGN_GROUP, sign.name, buf, {lnum: sign.lnum, priority: SIGN_PRIORITY})
    next[key] = {id: id, lnum: sign.lnum, name: sign.name}
  endfor

  for entry in values(previous)
    sign_unplace(SIGN_GROUP, {buffer: buf, id: entry.id})
  endfor

  state.last_signs = next
enddef

def FindGitRoot(filedir: string): string
  if has_key(root_by_dir, filedir)
    return root_by_dir[filedir]
  endif

  var marker = findfile('.git', filedir .. ';')
  if empty(marker)
    marker = finddir('.git', filedir .. ';')
  endif

  var root = ''
  if !empty(marker)
    var resolved = substitute(fnamemodify(marker, ':p'), '/$', '', '')
    root = fnamemodify(resolved, ':t') ==# '.git' ? fnamemodify(resolved, ':h') : ''
  endif
  root_by_dir[filedir] = root
  return root
enddef

def RelativePath(root: string, file: string): string
  if has_key(relpath_by_file, file)
    return relpath_by_file[file]
  endif
  if empty(root)
    return ''
  endif
  var prefix = root .. '/'
  var relpath = stridx(file, prefix) == 0 ? file[len(prefix) : ] : ''
  relpath_by_file[file] = relpath
  return relpath
enddef

def IsEligibleBuffer(buf: number): bool
  if !g:gitsign_enable
    return false
  endif
  if !bufexists(buf)
    return false
  endif
  if getbufvar(buf, '&buftype') !=# ''
    return false
  endif
  if getbufvar(buf, '&diff')
    return false
  endif
  return true
enddef

def BufferFile(buf: number): string
  var file = bufname(buf)
  if empty(file)
    return ''
  endif
  return fnamemodify(file, ':p')
enddef

def GitFile(file: string): string
  if empty(file)
    return ''
  endif
  return resolve(file)
enddef

def BufferBytes(buf: number, file: string): number
  if !getbufvar(buf, '&modified')
    return getfsize(file)
  endif

  if buf == bufnr('%')
    return max([0, line2byte(line('$') + 1) - 1])
  endif

  var lines = getbufline(buf, 1, '$')
  var size = len(lines)
  for line in lines
    size += strlen(line)
  endfor
  return size
enddef

def BufferTooLarge(buf: number, file: string): bool
  var max_bytes = g:gitsign_max_file_bytes
  if max_bytes > 0
    var size = BufferBytes(buf, file)
    if size > max_bytes
      return true
    endif
  endif

  var max_lines = g:gitsign_max_file_lines
  var info = getbufinfo(buf)
  if max_lines > 0 && !empty(info)
    var line_count = info[0].linecount
    if line_count > max_lines
      return true
    endif
  endif
  return false
enddef

def StartJob(buf: number, mode: string, argv: list<string>, stdout_file: string, stderr_file: string, ExitCbFactory: func)
  var state = EnsureState(buf)
  StopJob(buf)
  state.job_mode = mode
  state.job_seq += 1
  var seq = state.job_seq
  var job = job_start(argv, {
    out_io: 'file',
    out_name: stdout_file,
    err_io: 'file',
    err_name: stderr_file,
    exit_cb: ExitCbFactory(seq),
  })
  if type(job) != v:t_job
    state.job_mode = ''
    return
  endif
  state.job = job
enddef

def ReadLines(path: string): list<string>
  return filereadable(path) ? readfile(path) : []
enddef

def InvalidateHeadCache(root: string, relpath: string)
  var key = root .. "\n" .. relpath
  if !has_key(head_cache, key)
    return
  endif
  var entry = head_cache[key]
  DeleteFileIfExists(get(entry, 'path', ''))
  remove(head_cache, key)
enddef

def UseHeadCache(buf: number, generation: number)
  var state = BufState(buf)
  if empty(state) || state.generation != generation
    return
  endif

  StartHeadResolveJob(buf, generation)
enddef

def CompleteJob(buf: number, finished_seq: number)
  var state = BufState(buf)
  if empty(state)
    return
  endif
  if state.job_seq == finished_seq
    state.job = v:none
    state.job_mode = ''
  endif
enddef

def IsJobRunning(buf: number): bool
  var state = BufState(buf)
  return !empty(state) && type(state.job) == v:t_job && job_status(state.job) ==# 'run'
enddef

def MaybeRunPendingUpdate(buf: number)
  var state = BufState(buf)
  if empty(state) || state.timer != -1 || IsJobRunning(buf)
    return
  endif

  var generation = state.pending_generation
  if generation < 0
    return
  endif
  state.pending_generation = -1
  RunUpdate(buf, generation)
  StartCooldown(buf)
enddef

def HandleDiffResult(buf: number, finished_seq: number, generation: number, stdout_file: string, stderr_file: string)
  var state = BufState(buf)
  CompleteJob(buf, finished_seq)
  DeleteFileIfExists(stderr_file)
  if empty(state) || state.generation != generation || !bufexists(buf)
    DeleteFileIfExists(stdout_file)
    MaybeRunPendingUpdate(buf)
    return
  endif

  var diff = ReadLines(stdout_file)
  DeleteFileIfExists(stdout_file)

  if !IsEligibleBuffer(buf)
    ResetBuffer(buf)
    return
  endif

  ApplySigns(buf, ParseDiff(diff))
  MaybeRunPendingUpdate(buf)
enddef

def StartSavedDiffJob(buf: number, generation: number)
  var state = EnsureState(buf)
  var stdout_file = tempname()
  var stderr_file = tempname()
  AddTempfile(buf, stdout_file)
  AddTempfile(buf, stderr_file)
  StartJob(
    buf,
    MODE_SAVED,
    ['git', '-C', state.repo_root, 'diff', '--no-color', '--no-ext-diff', '-U0', '--', state.relpath],
    stdout_file,
    stderr_file,
    (seq) => (_, status) => {
      if status > 1
        DeleteFileIfExists(stdout_file)
        DeleteFileIfExists(stderr_file)
        CompleteJob(buf, seq)
        MaybeRunPendingUpdate(buf)
        return
      endif
      HandleDiffResult(buf, seq, generation, stdout_file, stderr_file)
    }
  )
enddef

def StartModifiedDiffJob(buf: number, generation: number, basefile: string)
  var state = EnsureState(buf)
  if state.generation != generation
    return
  endif

  var current_file = tempname()
  var stdout_file = tempname()
  var stderr_file = tempname()
  AddTempfile(buf, current_file)
  AddTempfile(buf, stdout_file)
  AddTempfile(buf, stderr_file)
  writefile(getbufline(buf, 1, '$'), current_file)

  StartJob(
    buf,
    MODE_MODIFIED,
    ['diff', '-U0', basefile, current_file],
    stdout_file,
    stderr_file,
    (seq) => (_, status) => {
      DeleteFileIfExists(current_file)
      if status > 1
        DeleteFileIfExists(stdout_file)
        DeleteFileIfExists(stderr_file)
        CompleteJob(buf, seq)
        MaybeRunPendingUpdate(buf)
        return
      endif
      HandleDiffResult(buf, seq, generation, stdout_file, stderr_file)
    }
  )
enddef

def StartEmptyBaseDiffJob(buf: number, generation: number, head_oid: string)
  var basefile = tempname()
  writefile([], basefile)

  var state = BufState(buf)
  if empty(state) || state.generation != generation
    DeleteFileIfExists(basefile)
    return
  endif

  var head_key = state.repo_root .. "\n" .. state.relpath
  var old_entry = get(head_cache, head_key, {})
  DeleteFileIfExists(get(old_entry, 'path', ''))
  head_cache[head_key] = {path: basefile, head_oid: head_oid}
  AddTempfile(buf, basefile)
  StartModifiedDiffJob(buf, generation, basefile)
enddef

def StartShowJob(buf: number, generation: number, head_oid: string)
  var state = EnsureState(buf)
  if state.generation != generation
    return
  endif

  var stdout_file = tempname()
  var stderr_file = tempname()
  AddTempfile(buf, stdout_file)
  AddTempfile(buf, stderr_file)

  StartJob(
    buf,
    MODE_SHOW,
    ['git', '-C', state.repo_root, 'show', head_oid .. ':' .. state.relpath],
    stdout_file,
    stderr_file,
    (seq) => (_, status) => {
      CompleteJob(buf, seq)
      DeleteFileIfExists(stderr_file)

      var current = BufState(buf)
      if empty(current) || current.generation != generation
        DeleteFileIfExists(stdout_file)
        MaybeRunPendingUpdate(buf)
        return
      endif

      var head_key = current.repo_root .. "\n" .. current.relpath
      var basefile = tempname()
      if status == 0
        writefile(ReadLines(stdout_file), basefile)
      else
        writefile([], basefile)
      endif

      var old_entry = get(head_cache, head_key, {})
      DeleteFileIfExists(get(old_entry, 'path', ''))
      head_cache[head_key] = {path: basefile, head_oid: head_oid}
      AddTempfile(buf, basefile)
      DeleteFileIfExists(stdout_file)
      StartModifiedDiffJob(buf, generation, basefile)
    }
  )
enddef

def StartHeadResolveJob(buf: number, generation: number)
  var state = EnsureState(buf)
  if state.generation != generation
    return
  endif

  var stdout_file = tempname()
  var stderr_file = tempname()
  AddTempfile(buf, stdout_file)
  AddTempfile(buf, stderr_file)

  StartJob(
    buf,
    MODE_HEAD,
    ['git', '-C', state.repo_root, 'rev-parse', '--verify', 'HEAD'],
    stdout_file,
    stderr_file,
    (seq) => (_, status) => {
      CompleteJob(buf, seq)
      DeleteFileIfExists(stderr_file)

      var current = BufState(buf)
      if empty(current) || current.generation != generation
        DeleteFileIfExists(stdout_file)
        MaybeRunPendingUpdate(buf)
        return
      endif

      var head_oid = ''
      if status == 0
        var lines = ReadLines(stdout_file)
        if !empty(lines)
          head_oid = trim(lines[0])
        endif
      endif
      DeleteFileIfExists(stdout_file)

      var head_key = current.repo_root .. "\n" .. current.relpath
      var entry = get(head_cache, head_key, {})
      if !empty(entry) && get(entry, 'head_oid', '') ==# head_oid && filereadable(get(entry, 'path', ''))
        StartModifiedDiffJob(buf, generation, entry.path)
        return
      endif

      InvalidateHeadCache(current.repo_root, current.relpath)
      if empty(head_oid)
        StartEmptyBaseDiffJob(buf, generation, head_oid)
        return
      endif
      StartShowJob(buf, generation, head_oid)
    }
  )
enddef

def StartCooldown(buf: number)
  var state = BufState(buf)
  if empty(state)
    return
  endif

  # Delay queued retries after an update; do not delay the first one.
  var delay = g:gitsign_cooldown_ms
  if delay <= 0
    state.timer = -1
    return
  endif

  if state.timer != -1
    timer_stop(state.timer)
  endif
  state.timer = timer_start(delay, (_) => OnCooldownExpire(buf))
enddef

def OnCooldownExpire(buf: number)
  var state = BufState(buf)
  if empty(state)
    return
  endif
  state.timer = -1

  if state.pending_generation < 0 || IsJobRunning(buf)
    return
  endif
  MaybeRunPendingUpdate(buf)
enddef

def ScheduleUpdate(buf: number, immediate: bool = false)
  if !IsEligibleBuffer(buf)
    ResetBuffer(buf)
    return
  endif

  var file = BufferFile(buf)
  if empty(file) || !filereadable(file)
    ResetBuffer(buf)
    return
  endif
  var git_file = GitFile(file)
  if empty(git_file) || !filereadable(git_file)
    ResetBuffer(buf)
    return
  endif

  if BufferTooLarge(buf, file)
    ResetBuffer(buf)
    return
  endif

  var root = FindGitRoot(fnamemodify(git_file, ':h'))
  var relpath = RelativePath(root, git_file)
  if empty(root) || empty(relpath)
    ResetBuffer(buf)
    return
  endif

  var state = EnsureState(buf)
  state.file = file
  state.repo_root = root
  state.relpath = relpath
  state.generation += 1

  if immediate
    StopTimer(buf)
    RunUpdate(buf, state.generation)
    return
  endif

  if state.timer != -1
    state.pending_generation = state.generation
    StartCooldown(buf)
    return
  endif

  if IsJobRunning(buf)
    state.pending_generation = state.generation
    return
  endif

  # Normal edits use a leading update, then coalesce follow-up edits.
  RunUpdate(buf, state.generation)
  StartCooldown(buf)
enddef

def RunUpdate(buf: number, generation: number)
  var state = BufState(buf)
  if empty(state) || state.generation != generation
    return
  endif

  if !IsEligibleBuffer(buf)
    ResetBuffer(buf)
    return
  endif

  if getbufvar(buf, '&modified')
    if !g:gitsign_enable_modified_buffer
      ClearSigns(buf)
      return
    endif
    UseHeadCache(buf, generation)
    return
  endif

  StartSavedDiffJob(buf, generation)
enddef

def CleanupBuffer(buf: number)
  ResetBuffer(buf)
  var key = string(buf)
  if has_key(state_by_buf, key)
    remove(state_by_buf, key)
  endif
enddef

def InvalidateBufferHead(buf: number)
  var state = BufState(buf)
  if empty(state) || empty(state.repo_root) || empty(state.relpath)
    return
  endif
  InvalidateHeadCache(state.repo_root, state.relpath)
enddef

def g:GitSignUpdate(buf: number = bufnr('%'))
  ScheduleUpdate(buf, true)
enddef

def g:GitSignSchedule(buf: number = bufnr('%'))
  ScheduleUpdate(buf, false)
enddef

def g:GitSignInvalidate(buf: number = bufnr('%'))
  InvalidateBufferHead(buf)
  ScheduleUpdate(buf, true)
enddef

command! GitSignRefresh call g:GitSignInvalidate()

augroup gitsign_vim9
  autocmd!
  autocmd BufReadPost * call g:GitSignUpdate(expand('<abuf>')->str2nr())
  autocmd BufWritePost * call g:GitSignInvalidate(expand('<abuf>')->str2nr())
  autocmd TextChanged,TextChangedI,CursorHold,CursorHoldI * call g:GitSignSchedule(expand('<abuf>')->str2nr())
  autocmd BufDelete,BufWipeout * call CleanupBuffer(expand('<abuf>')->str2nr())
augroup END
