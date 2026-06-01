vim9script

# Keep Copilot disabled by default, and only allow it for commit messages.
g:copilot_filetypes = {
  '*': v:false,
  gitcommit: v:true,
}
