vim9script

nnoremap <F3> <Cmd>nohlsearch<CR>

nnoremap <leader>df <Cmd>LspGotoDefinition<CR>
nnoremap <leader>pd <Cmd>LspPeekDefinition<CR>
nnoremap <leader>dic <Cmd>LspDiag current<CR>
nnoremap <leader>dc <Cmd>LspGotoDeclaration<CR>
nnoremap <leader>re <Cmd>LspShowReferences<CR>
nnoremap <leader>pr <Cmd>LspPeekReferences<CR>
nnoremap <leader>h <Cmd>LspHover<CR>
nnoremap <leader>rn <Cmd>LspRename<CR>
nnoremap <leader>ac <Cmd>LspCodeAction<CR>
nnoremap <leader>at <Cmd>call g:TyposCodeAction()<CR>
nnoremap <leader>f <Cmd>LspFormat<CR>
nnoremap <leader>[ <Cmd>LspDiag prev<CR>
nnoremap <leader>] <Cmd>LspDiag next<CR>
nnoremap <leader>dis <Cmd>LspDiag show<CR>
nnoremap <leader>ol <Cmd>LspOutline<CR>
nnoremap <leader>ds <Cmd>LspDocumentSymbol<CR>
nnoremap <leader>t <Cmd>LspGotoTypeDef<CR>
nnoremap <leader>im <Cmd>LspGotoImpl<CR>
nnoremap <leader>ih <Cmd>LspInlayHints toggle<CR>
nnoremap <leader>se <Cmd>LspSelectionExpand<CR>
xnoremap <leader>se <Cmd>LspSelectionExpand<CR>
nnoremap <leader>ss <Cmd>LspSelectionShrink<CR>
xnoremap <leader>ss <Cmd>LspSelectionShrink<CR>
nnoremap <leader>ws <Cmd>LspSymbolSearch<CR>
