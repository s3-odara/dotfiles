vim9script

g:easyjump_default_keymap = false

nnoremap <silent> <leader>j <Plug>EasyjumpJump;
onoremap <silent> <leader>j <Plug>EasyjumpJump;
vnoremap <silent> <leader>j <Plug>EasyjumpJump;
nnoremap <silent> <leader>J 2<Plug>EasyjumpJump;
onoremap <silent> <leader>J 2<Plug>EasyjumpJump;
vnoremap <silent> <leader>J 2<Plug>EasyjumpJump;

highlight EasyJump guifg=#11eb9c gui=bold cterm=bold
