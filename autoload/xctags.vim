let g:xctags#version = '0.0.1'

" setup {{{ "
let s:project_dir = ''
function! xctags#setup()
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
 
" init {{{ "
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
" }}} "

" cache tags {{{ "
let s:xctags_cache = {}
let s:tags = &tags
function! xctags#cache()
    if !s:CheckSupportedLanguage()
        exec "silent set tags=" . s:tags
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

" update {{{1 "
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
    " TODO: how to optimize?
    let tagsfile = s:GetTagsFileByFileType(&ft)
    let [headers, indexer] = s:ReadTagsFile(tagsfile)
    let newlines = s:ParseLines(resp)
    let indexer[cfile] = newlines
    let lines = []
    for key in keys(indexer)
        call extend(lines, get(indexer, key, []))
    endfor

    " write tagsfile
    call s:WriteTagsFile(tagsfile, headers, lines)
endfunction
" }}} "

" WriteTagsFile {{{ "
function! s:WriteTagsFile(tagsfile, headers, lines)
    call map(a:lines, 's:JoinLine(v:val)')

    " sort it
    call sort(a:lines)

    let result = []
    call extend(result, a:headers)
    call extend(result, a:lines)

    return writefile(result, a:tagsfile)
endfunction
" }}} "

" ReadTagsFile {{{ "
function! s:ReadTagsFile(tagsfile)
    let headers = []
    "let lines = []
    let indexer = {}

    for line in readfile(a:tagsfile)
        if line =~# '^!_TAG_'
            call add(headers, line)
        else
            let entry = s:ParseLine(line)
            if !empty(entry)
                if !has_key(indexer, entry[1])
                    let indexer[entry[1]] = []
                endif
                let index = get(indexer, entry[1], [])
                call add(index, line)
                "call add(lines, line)
            endif
        endif
    endfor

    return [headers, indexer]
endfunction
" }}} "


" ParseLine {{{ "
function! s:ParseLine(line)
    let fields = split(a:line, "\t")
    return len(fields) >= 3 ? fields : []
endfunction
" }}} "

" ParseLines {{{ "
function! s:ParseLines(lines)
    let lines = split(a:lines, "\n")
    call map(lines, 's:ParseLine(v:val)')

    return filter(lines, '!empty(v:val)')
endfunction
" }}} "

" JoinLine {{{ "
function! s:JoinLine(value)
    return type(a:value) == type([]) ? join(a:value, "\t") : a:value
endfunction
" }}} "

" GetTagsFileByFileType {{{ "
function! s:GetTagsFileByFileType(cft)
    if a:cft == ''
        return
    endif
    return s:NormalizePath(g:xctags_tags_directory_name . '/' . a:cft)
endfunction
" }}} "

" CheckSupportedLanguage {{{ "
function! s:CheckSupportedLanguage()
    if &ft == '' || !exists('g:xctags_language') || empty(get(g:xctags_language, &ft, {}))
        return 0
    endif
    return 1
endfunction
" }}} "

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
    " if not file specified, parse all identifiers files
    if a:cfile == ''
        " for all matched files
        " `find` just support *nix os
        let identifiers = get(config, 'identifiers', [])
        let prefix = [
            \'find -E ' . s:project_dir . ' -regex ".*\.(' . join(identifiers, '|') . ')"', 
            \'|', 
            \'xargs'
            \]
        unlet identifiers
        let cmdline = prefix + cmdline
        " configurable tagfile path?
        call add(cmdline, '-f ' . a:tagsfile)
    else
        " for one specificed file
        let filename = s:NormalizePath(a:cfile)
        " incrementally update, put to standout first
        call add(cmdline, '-f-')
        call add(cmdline, filename)
    endif

    return join(cmdline)
endfunction
" }}} "


 



" vim: ts=4 sw=4 foldmethod=marker
