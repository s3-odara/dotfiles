vim9script

def g:VsnipSessionActive(): bool
  try
    return vsnip#jumpable(1) || vsnip#jumpable(-1)
  catch
    return v:false
  endtry
enddef

imap <expr> <C-l> vsnip#available(1) ? "\<Plug>(vsnip-expand-or-jump)" : "\<C-l>"
smap <expr> <C-l> vsnip#available(1) ? "\<Plug>(vsnip-expand-or-jump)" : "\<C-l>"
inoremap <expr> <Space> pumvisible() && g:VsnipSessionActive() ? "\<C-y>" : "\<Space>"
imap <expr> <Tab> pumvisible() ? "\<C-n>" : vsnip#jumpable(1) ? "\<Plug>(vsnip-jump-next)" : "\<Tab>"
smap <expr> <Tab> vsnip#jumpable(1) ? "\<Plug>(vsnip-jump-next)" : "\<Tab>"
imap <expr> <S-Tab> pumvisible() ? "\<C-p>" : vsnip#jumpable(-1) ? "\<Plug>(vsnip-jump-prev)" : "\<S-Tab>"
smap <expr> <S-Tab> vsnip#jumpable(-1) ? "\<Plug>(vsnip-jump-prev)" : "\<S-Tab>"
