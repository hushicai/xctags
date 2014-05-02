let g:xctags#version = '0.0.1'

" register project {{{ "
let s:project_dir = ''
function! xctags#register()
    let config = s:FindProjConfigFile()
    if config != ''
        exec "silent source" . config
        let config = resolve(getcwd() . '/' . config)
        let projDir = fnamemodify(config, ':h')
        let s:project_dir = projDir
    endif
    return config
endfunction
" }}} "
 
function! xctags#init() 
    if !exists('g:xctags_language') || empty(g:xctags_language)
        return
    endif

    let tagsDir = s:NormalizePath(g:xctags_tags_directory_name)
    if !isdirectory(tagsDir)
        exec "silent !mkdir " . tagsDir
    endif

    for key in keys(g:xctags_language) 
        let tagsfile = s:NormalizePath(g:xctags_tags_directory_name . '/' . key)
        " generate tags in local directory, classify by filetype
        " generate tags once for the first time
        if !filereadable(tagsfile)
            let cmd = s:BuildCmdLine(key, '', tagsfile)
            exec "silent !" . cmd
        endif
    endfor
endfunction

" cache tags {{{ "
let s:xctags_cache = {}
let s:tags = &tags
function! xctags#cache()
    if !s:CheckSupportedLanguage()
        return
    endif
    let tagsfile = s:GetTagsFileByFileType(&ft)
    exec "silent set tags=" .  tagsfile . ',' . s:tags

    let cfile = expand('%:p')
    let cmdline = s:BuildCmdLine(&ft, cfile, '')
    let resp = system(cmdline)
    if get(s:xctags_cache, cfile, '') == ''
        let s:xctags_cache[cfile] = sha256(resp)
    endif
endfunction
" }}} "

function! xctags#update()
    if !s:CheckSupportedLanguage()
        return
    endif
    let cfile = expand('%:p')
    let cmdline = s:BuildCmdLine(&ft, cfile, '')
    let resp = system(cmdline)
    let cachesha = get(s:xctags_cache, cfile, '')
    let newcachesha = sha256(resp)
    if cachesha != '' && cachesha == newcachesha
        " no updates
        return
    endif
    let s:xctags_cache[cfile] = newcachesha
    " update tags
    let tagsfile = s:GetTagsFileByFileType(&ft)
    " first, remove it
    call s:RemoveTags(tagsfile, cfile)
    " then, append new tags
    call s:AddTags(tagsfile, resp)
endfunction

function! s:GetTagsFileByFileType(cft)
    if a:cft == ''
        return
    endif
    return s:NormalizePath(g:xctags_tags_directory_name . '/' . a:cft)
endfunction

function! s:CheckSupportedLanguage()
    if &ft == '' || empty(get(g:xctags_language, &ft, {}))
        return 0
    endif
    return 1
endfunction

" FindProjConfigFile {{{ "
function! s:FindProjConfigFile()
    let parent = 1
    let config = g:xctags_config_file_name
    while parent <= 8
        if filereadable(config)
            return config
        endif
        let parent = parent + 1
        let config = '../' . config
    endwhile
endfunction
" }}} "
 
" NormalizePath {{{ "
function! s:NormalizePath(posix)
    " is an absolute path
    if a:posix =~ '^/'
        return a:posix
    endif
    return resolve(s:project_dir . '/' . a:posix)
endfunction
" }}} "

" BuildCmdLine {{{ "
function! s:BuildCmdLine(language, cfile, tagsfile)
    let config = g:xctags_language[a:language]
    let program = get(config, 'cmd', g:xctags_ctags_cmd)
    let args = get(config, 'args', [])
    let cmdline = [program] + args
    " if not file specificed, parse all identifiers files
    if a:cfile == ''
        " `find` just support *nix os
        let prefix = ['find ' . s:project_dir . ' -type f', '|', 'xargs']
        let cmdline = prefix + cmdline
        let identifiers = get(config, 'identifiers', [])
        call add(cmdline, '--sort=yes')
        call add(cmdline, '-I "' . join(identifiers) . '"')
        " configurable tagfile path?
        call add(cmdline, '-f ' . a:tagsfile)
        "call add(cmdline, '-R')
    else
        let filename = s:NormalizePath(a:cfile)
        call add(cmdline, '--sort=no')
        " incrementally update, put to standout first
        call add(cmdline, '-f-')
        call add(cmdline, filename)
    endif

    return join(cmdline)
endfunction
" }}} "

function! s:RemoveTags(tagsfile, cfile)
  let filename = s:NormalizePath(a:cfile)
  let filename = escape(filename, './')
  let cmd = 'sed -i '' "/' . filename . '/d" "' . a:tagsfile . '"'
  let resp = system(cmd)
endfunction

function! s:AddTags(tagsfile, lines)
    echom lines
    let cmd = 'silent !echo "' . escape(a:lines,'"/') . '" >> ' .a:tagsfile
    echom cmd
    let resp = system(cmd)
endfunction

" vim: ts=4 sw=4 foldmethod=marker
