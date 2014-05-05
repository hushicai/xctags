let g:xctags#version = '0.0.1'

" log {{{ "
function! xctags#log(msg)
    if g:xctags_debug
        echom a:msg
    endif
endfunction
" }}} log "

" setup {{{ "
" every path is relative to the `project_dir`
let s:project_dir = ''
function! xctags#setup()
    call xctags#log('setting up project...')
    let config = s:FindProjConfigFile()
    if config != ''
        exec "silent source " . config
        let config = resolve(getcwd() . '/' . config)
        let project_dir = fnamemodify(config, ':h')
        let s:project_dir = project_dir
        call xctags#log('found a project: ' . project_dir)
    else
        call xctags#log('no project found!')
    endif
    return config
endfunction
" }}} "

" clean {{{ "
function! xctags#clean()
    " nothing for the moment
endfunction
" }}} clean"
 
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

" cache {{{ "
let s:xctags_cache_ftime = {}
let s:xctags_cache_sha256 = {}
function! xctags#cache()
    if !s:CheckSupportedLanguage()
        return
    endif

    call xctags#log("cahched: " . string(s:xctags_cache_sha256))

    let filename = expand('%:p')
    let s:xctags_cache_ftime[filename] = getftime(filename)

    let sha = get(s:xctags_cache_sha256, filename, '')
    if sha != ''
        call xctags#log('tags cached!')
        return
    endif

    call xctags#log('caching tags...')

    return s:RunCtags(&ft, '.cache')
endfunction
" }}} cache "
 
" update {{{ "
function! xctags#update()
    if !s:CheckSupportedLanguage()
        return
    endif

    let filename = expand('%:p')
    let ftime_old = get(s:xctags_cache_ftime, filename, 0)
    let ftime_new = getftime(filename)

    if ftime_old == ftime_new
        call xctags#log("file has not change, there is no need to update.")
        return
    endif

    call xctags#log('file written, going to check tags...')

    return s:RunCtags(&ft, '.check')
endfunction
" }}} "

" schedule {{{ "
let s:xctags_schedule_last_time = 0
function! xctags#schedule()
    if !s:CheckSupportedLanguage()
        return
    endif

    " must be initialized at the very beginning
    if !filereadable(s:GetTagsFileByFileType(&ft))
        return
    endif

    call xctags#log('begin a frame.')

    " cache it first
    if s:CacheTags() == 0
        call xctags#log('tags not cached,  go to next frame.')
        return
    endif

    " for update?
    let now_time = localtime()
    if s:xctags_schedule_last_time != 0 && (now_time - s:xctags_schedule_last_time < g:xctags_schedule_interval)
        return
    endif
    let s:xctags_schedule_last_time = now_time

    " then check
    if s:CheckTags() == 0
        call xctags#log('tags not changed, go to next frame.')
        return
    endif

    " finally update
    if s:UpdateTags() == 0
        call xctags#log('tags not updated, go to next frame')
        return
    endif

    call xctags#log('complete a frame.')

    " anything else
endfunction
" }}} schedule "
 
" exec ctags in shell {{{ " 
function! s:ExecCtags(cft)
    let tagsfile = s:GetTagsFileByFileType(a:cft)

    " update all the time?
    if !filereadable(tagsfile)
        let cmdline = s:BuildCmdLine(a:cft, tagsfile, '')
        silent exec "!" . cmdline
    endif
     
    return tagsfile
endfunction
" }}} "

" run ctags in vim {{{ "
function! s:RunCtags(cft, ext)
    let cmdline = s:BuildCmdLine(a:cft, '-', a:ext)
    return system(cmdline)
endfunction
" }}} "

" cache tags {{{ "
function! s:CacheTags()
    let filename = expand('%:p')
    let sha = get(s:xctags_cache_sha256, filename, '')
    if sha != ''
        return 1
    else
        let tempname = s:GetTempname('.cache')
        if filereadable(tempname)
            let s:xctags_cache_sha256[filename] = sha256(join(readfile(tempname), '\n'))
            call xctags#log('caching tags, done!')
            call delete(tempname)
            return 1
        else
            return 0
        endif
    endif
endfunction
" }}} cache tags "

" check tags {{{ "
function! s:CheckTags()
    let tempname = s:GetTempname('.check')
    if filereadable(tempname)
        let filename = expand('%:p')
        let sha = get(s:xctags_cache_sha256, filename, '')
        let newsha = sha256(join(readfile(tempname), '\n'))
        if sha != '' && sha == newsha
            call xctags#log('tags have not been changed.')
            call delete(tempname)
            return 0
        endif
        call xctags#log("tags changed, going to update...")

        return 1
    else 
        return 0
    endif
endfunction
" }}} check tags "

" update tags {{{ "
function! s:UpdateTags()
    let tagsfile = s:GetTagsFileByFileType(&ft)
    let tempname = s:GetTempname('.check')
    if filereadable(tempname)
        let filename = expand('%:p')
        " update cache here to make sure that cache and tagsfile is consistent
        let s:xctags_cache_sha256[filename] = sha256(join(readfile(tempname), '\n'))
        let cmd_remove_tags = "sed -i '' '/" . escape(filename, './') . "/d' " . tagsfile
        let cmd_add_tags = 'cat ' . tempname . ' >> ' . tagsfile
        let cmd_remove_tempname = "rm " . tempname
        let cmd = '!{' . cmd_remove_tags . ';' . cmd_add_tags .  ';' . cmd_remove_tempname . '} &'
        call xctags#log("updating tags: " . cmd)
        silent exec cmd
        "call s:RemoveOldTags()
        "call s:AddNewTags()
        call xctags#log('update tags, done!')
        return 1
    else
        return 0
    endif
endfunction
" }}} update tags "

" remove old tags {{{ "
function! s:RemoveOldTags()
    let filename = expand('%:p')
    let tagsfile = s:GetTagsFileByFileType(&ft)
    let cmd = "!sed -i '' '/" . escape(filename, './') . "/d' " . tagsfile . ' '
    call xctags#log('remove old tags: ' . cmd)
    silent exec cmd
endfunction
" }}} remove old tags "

" add new tags {{{ "
function! s:AddNewTags()
    let tempname = s:GetTempname('.check')
    let tagsfile = s:GetTagsFileByFileType(&ft)
    let cmd = '!cat ' . tempname . ' >> ' . tagsfile . ' '
    call xctags#log('add new tags: ' . cmd)
    silent exec cmd
endfunction
" }}} add new tags "
 
" get temp filename {{{ "
function! s:GetTempname(ext)
    if !isdirectory($HOME . '/tmp')
        silent exec "!mkdir" . $HOME . "/tmp"
    endif
    return $HOME . "/tmp/" . sha256(expand('%:p')) . a:ext
endfunction
" }}} create temp filename "

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
function! s:BuildCmdLine(cft, tagsfile, ext)
    let ft_config = g:xctags_language[a:cft]
    let program = get(ft_config, 'cmd', g:xctags_ctags_cmd)
    let args = get(ft_config, 'args', [])
    let cmdline = [program] + args

    call add(cmdline, '-f ' . a:tagsfile)
    " if no sort
    call add(cmdline, '--sort=no')

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
    else
        " usually, for one specified file
        let filename = expand('%:p')
        " incrementally update, put to standout first
        call add(cmdline, filename)
        call add(cmdline, ' > ' . s:GetTempname(a:ext))
    endif

    " async
    call add(cmdline, '&')

    return join(cmdline)
endfunction
" }}} "




" vim: ts=4 sw=4 foldmethod=marker
