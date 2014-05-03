let g:xctags#version = '0.0.1'

" setup {{{ "
" every path is relative the `project_dir`
let s:project_dir = ''
function! xctags#setup()
    let config = s:FindProjConfigFile()
    if config != ''
        exec "silent source " . config
        let config = resolve(getcwd() . '/' . config)
        let project_dir = fnamemodify(config, ':h')
        let s:project_dir = project_dir
    endif
    return config
endfunction
" }}} "
 
" init {{{ "
function! xctags#init() 
    if !exists('g:xctags_language') || empty(g:xctags_language)
        return
    endif

    let tags_dir = s:NormalizePath(g:xctags_tags_directory_name)
    if !isdirectory(tags_dir)
        exec "silent !mkdir " . tags_dir
    endif

    " generate tags in local project directory, classify by filetype
    for cft in keys(g:xctags_language) 
        call s:ExecCtags(cft)
    endfor
endfunction
" }}} "
 
" set tags {{{ "
let s:tags = &tags
function! xctags#set()
    if s:CheckSupportedLanguage()
        let tagsfile = s:GetTagsFileByFileType(&ft)
    else 
        let tagsfile = ''
    endif
    exec "silent set tags=" .  (tagsfile != '' ? (tagsfile . ',') : '') . s:tags
endfunction
" }}} "
 
" cache tags {{{ "
let s:xctags_cache = {}
function! xctags#cache()
    if !s:CheckSupportedLanguage()
        return
    endif

    let resp = s:RunCtags(&ft)
    let cfile = expand('%:p')
    if get(s:xctags_cache, cfile, '') == ''
        let s:xctags_cache[cfile] = sha256(resp)
    endif
endfunction
" }}} "

" update {{{ "
function! xctags#update()
    if !s:CheckSupportedLanguage()
        return
    endif
    let tagsfile = s:GetTagsFileByFileType(&ft)
    let cfile = expand('%:p')
    let cachesha = get(s:xctags_cache, cfile, '')

    " run one more ctags program
    let resp = s:RunCtags(&ft)
    let newcachesha = sha256(resp)

    " check if outdate
    if cachesha != '' && cachesha == newcachesha
        " no updates
        return
    endif

    " if tagsfile doesn't exist
    " TODO: create a new one?
    if !filereadable(tagsfile)
        return
    endif

    " update cache
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
 
" exec ctags in shell {{{ " 
function! s:ExecCtags(cft)
    let tagsfile = s:GetTagsFileByFileType(a:cft)

    " update all the time?
    if !filereadable(tagsfile)
        let cmdline = s:BuildCmdLine(a:cft, tagsfile)
        exec "silent !" . cmdline
    endif
     
    return tagsfile
endfunction
" }}} "

" run ctags in vim {{{ "
function! s:RunCtags(cft)
    let cmdline = s:BuildCmdLine(a:cft, '-')
    return system(cmdline)
endfunction
" }}} "

" WriteTagsFile {{{ "
function! s:WriteTagsFile(tagsfile, headers, lines)
    " force it sorted
    " ignore `--sort=no` option
    " treat it sorted always
    " this is the default way.
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
" everything thiing is absolute. file path,tag path,tags option,etc.
function! s:NormalizePath(posix)
    " is an absolute path
    if a:posix =~ '^/'
        return a:posix
    endif
    return resolve(s:project_dir . '/' . a:posix)
endfunction
" }}} "

" BuildCmdLine {{{ "
function! s:BuildCmdLine(cft, tagsfile)
    let ft_config = g:xctags_language[a:cft]
    let program = get(ft_config, 'cmd', g:xctags_ctags_cmd)
    let args = get(ft_config, 'args', [])
    let cmdline = [program] + args

    call add(cmdline, '-f ' . a:tagsfile)

    if a:tagsfile != '-'
        " for all matched files
        let identifiers = get(ft_config, 'identifiers', [])
        " `find` just support *nix os
        let prefix = [
            \'find -E ' . s:project_dir . ' -regex ".*\.(' . join(identifiers, '|') . ')"', 
            \'|', 
            \'xargs'
            \]
        unlet identifiers
        let cmdline = prefix + cmdline
        "call add(cmdline, '-f ' . a:tagsfile)
    else
        " usually, for one specified file
        let filename = expand('%:p')
        " incrementally update, put to standout first
        "call add(cmdline, '-f-')
        call add(cmdline, filename)
    endif

    return join(cmdline)
endfunction
" }}} "


 



" vim: ts=4 sw=4 foldmethod=marker
