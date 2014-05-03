" Don't source the plug-in when it's already been loaded or &compatible is set.
if &cp || exists('g:xctags_loaded')
  finish
endif

if !exists('g:xctags_ctags_cmd')
    let g:xctags_ctags_cmd = 'ctags'
endif

if !exists('g:xctags_config_file_name')
    let g:xctags_config_file_name = '.xctags'
endif

" relative to project dir
if !exists('g:xctags_tags_directory_name')
    let g:xctags_tags_directory_name = '.tags'
endif

if xctags#setup() == ''
    finish
endif

augroup xplugin
    autocmd!
    au VimEnter * call xctags#init()
    au BufRead * call xctags#set()
    au BufReadPost * call xctags#cache()
    au BufWritePost * call xctags#update()
augroup END

" Make sure the plug-in is only loaded once.
let g:xctags_loaded = 1




" vim: ts=4 sw=4 foldmethod=marker
