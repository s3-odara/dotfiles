vim9script

# gitcommit-only vim-ai helpers.

if exists('b:did_ai_commit_ftplugin')
  finish
endif
b:did_ai_commit_ftplugin = 1

packadd vim-ai
source ~/.vim/config/plugins/vim-ai.vim

var ai_commit_prompt = ''

def EditableBodyEnd(): number
  for lnum in range(1, line('$'))
    if getline(lnum) =~# '^#' || getline(lnum) =~# '^diff --git '
      return lnum - 1
    endif
  endfor

  return line('$')
enddef

def DeleteEditableBody(end_lnum: number): number
  if end_lnum < 1
    append(0, '')
    return 1
  endif

  deletebufline(bufnr('%'), 1, end_lnum)
  append(0, '')
  return 1
enddef

def Vibecommit(): void
  if empty($OPENROUTER_VIM_AI_API_KEY)
    echoerr 'Vibecommit: OPENROUTER_VIM_AI_API_KEY is not set.'
    return
  endif

  var diff = system(['git', '--no-pager', 'diff', '--staged'])
  if v:shell_error != 0
    echoerr 'Vibecommit: failed to read staged diff.'
    return
  endif
  if empty(trim(diff))
    echoerr 'Vibecommit: no staged diff found.'
    return
  endif

  ai_commit_prompt = join([
    '# Write a Conventional Commit message.',
    '',
    'Format:',
    '  <type>(<optional scope>): <subject>',
    '',
    '  <optional body>',
    '',
    '  <optional footer>',
    '',
    'Types:',
    '  feat, fix, docs, style, refactor, perf, test, build, ci, chore',
    '',
    'Scope:',
    '  - infer from staged files, module names, commands, or config names',
    '  - keep short and lowercase',
    '  - omit if unclear',
    '',
    'Subject:',
    '  - keep under 50 characters',
    '',
    'Body:',
    '  - explain why the change was needed',
    '  - wrap lines at 72 characters',
    '  - omit if the subject is enough',
    '',
    'Footer:',
    '  - use BREAKING CHANGE: if needed',
    '',
    diff,
  ], "\n")

  var end_lnum = EditableBodyEnd()
  DeleteEditableBody(end_lnum)
  cursor(1, 1)
  # vim-ai's complete runner appends after its received range end and then
  # jumps back there.  Call it with an explicit line-1 range so generated text
  # is inserted into the editable commit-message body, not near the cursor that
  # was active when :Vibecommit was invoked.
  execute ':1call vim_ai#AIRun(0, {}, ai_commit_prompt)'
enddef

command! -buffer Vibecommit Vibecommit()
