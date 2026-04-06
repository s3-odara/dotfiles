vim9script

g:easyjump_default_keymap = false

nnoremap <silent> <leader>je <Plug>EasyjumpJump;
onoremap <silent> <leader>je <Plug>EasyjumpJump;
vnoremap <silent> <leader>je <Plug>EasyjumpJump;
nnoremap <silent> <leader>JE 2<Plug>EasyjumpJump;
onoremap <silent> <leader>JE 2<Plug>EasyjumpJump;
vnoremap <silent> <leader>JE 2<Plug>EasyjumpJump;

highlight EasyJump guifg=#11eb9c gui=bold cterm=bold
