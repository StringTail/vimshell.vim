"=============================================================================
" FILE: vimshell.vim
" AUTHOR: Janakiraman .S <prince@india.ti.com>(Original)
"         Shougo Matsushita <Shougo.Matsu@gmail.com>(Modified)
" Last Modified: 03 Dec 2009
" Usage: Just source this file.
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
" Version: 5.38, for Vim 7.0
"=============================================================================

if !exists('g:VimShell_Prompt')
    let s:prompt = 'vimshell% '
else
    let s:prompt = g:VimShell_Prompt
endif
if !exists('g:VimShell_SecondaryPrompt')
    let s:secondary_prompt = '%% '
else
    let s:secondary_prompt = g:VimShell_SecondaryPrompt
endif
if !exists('g:VimShell_UserPrompt')
    let s:user_prompt = ''
else
    let s:user_prompt = g:VimShell_UserPrompt
endif

if !exists('g:VimShell_ExecuteFileList')
    let g:VimShell_ExecuteFileList = {}
endif

" Helper functions.
function! vimshell#set_execute_file(exts, program)"{{{
    for ext in split(a:exts, ',')
        let g:VimShell_ExecuteFileList[ext] = a:program
    endfor
endfunction"}}}

" Special functions."{{{
function! s:special_command(program, args, fd, other_info)"{{{
    let l:program = a:args[0]
    let l:arguments = a:args[1:]
    if has_key(g:vimshell#internal_func_table, l:program)
        " Internal commands.
        execute printf('call %s(l:program, l:arguments, a:is_interactive, a:has_head_spaces, a:other_info)', 
                    \ g:vimshell#internal_func_table[l:program])
    else
        call vimshell#execute_internal_command('exe', insert(l:arguments, l:program), a:fd, a:other_info)
    endif

    return 0
endfunction"}}}
function! s:special_internal(program, args, fd, other_info)"{{{
    if empty(a:args)
        " Print internal commands.
        for func_name in keys(g:vimshell#internal_func_table)
            call vimshell#print_line(func_name)
        endfor
    else
        let l:program = a:args[0]
        let l:arguments = a:args[1:]
        if has_key(g:vimshell#internal_func_table, l:program)
            " Internal commands.
            execute printf('call %s(l:program, l:arguments, a:is_interactive, a:has_head_spaces, a:other_info)', 
                        \ g:vimshell#internal_func_table[l:program])
        else
            " Error.
            call vimshell#error_line('', printf('Not found internal command "%s".', l:program))
        endif
    endif

    return 0
endfunction"}}}
"}}}

" VimShell plugin utility functions."{{{
function! vimshell#create_shell(split_flag, directory)"{{{
    let l:bufname = 'vimshell'
    let l:cnt = 2
    while bufexists(l:bufname)
        let l:bufname = printf('[%d]vimshell', l:cnt)
        let l:cnt += 1
    endwhile

    if a:split_flag
        execute 'split +setfiletype\ vimshell ' . l:bufname
        execute 'resize' . winheight(0)*g:VimShell_SplitHeight / 100
    else
        execute 'edit +setfiletype\ vimshell ' . l:bufname
    endif

    setlocal buftype=nofile
    setlocal noswapfile
    setlocal bufhidden=hide
    let &l:omnifunc = ''

    " Change current directory.
    let b:vimshell_save_dir = getcwd()
    let l:current = (a:directory != '')? a:directory : getcwd()
    lcd `=fnamemodify(l:current, ':p')`

    " Load history.
    if !filereadable(g:VimShell_HistoryPath)
        " Create file.
        call writefile([], g:VimShell_HistoryPath)
    endif
    let g:vimshell#hist_buffer = readfile(g:VimShell_HistoryPath)
    let s:hist_size = getfsize(g:VimShell_HistoryPath)

    if !exists('s:prev_numbered_list')
        let s:prev_numbered_list = []
    endif
    if !exists('s:prepre_numbered_list')
        let s:prepre_numbered_list = []
    endif
    if !exists('b:vimshell_alias_table')
        let b:vimshell_alias_table = {}
    endif
    if !exists('b:vimshell_galias_table')
        let b:vimshell_galias_table = {}
    endif
    if !exists('g:vimshell#internal_func_table')
        let g:vimshell#internal_func_table = {}

        " Search autoload.
        for list in split(globpath(&runtimepath, 'autoload/vimshell/internal/*.vim'), '\n')
            let l:func_name = fnamemodify(list, ':t:r')
            let g:vimshell#internal_func_table[l:func_name] = 'vimshell#internal#' . l:func_name . '#execute'
        endfor
    endif
    if !exists('g:vimshell#special_func_table')
        " Initialize table.
        let g:vimshell#special_func_table = {
                    \ 'command' : 's:special_command',
                    \ 'internal' : 's:special_internal',
                    \}

        " Search autoload.
        for list in split(globpath(&runtimepath, 'autoload/vimshell/special/*.vim'), '\n')
            let l:func_name = fnamemodify(list, ':t:r')
            let g:vimshell#special_func_table[l:func_name] = 'vimshell#special#' . l:func_name . '#execute'
        endfor
    endif
    if !exists('w:vimshell_directory_stack')
        let w:vimshell_directory_stack = []
        let w:vimshell_directory_stack[0] = getcwd()
    endif
    " Load rc file.
    if filereadable(g:VimShell_VimshrcPath) && !exists('b:vimshell_loaded_vimshrc')
        call vimshell#execute_internal_command('vimsh', [g:VimShell_VimshrcPath], {}, 
                    \{ 'has_head_spaces' : 0, 'is_interactive' : 0, 'is_background' : 0 })
        let b:vimshell_loaded_vimshrc = 1
    endif
    if !exists('b:vimshell_commandline_stack')
        let b:vimshell_commandline_stack = []
    endif
    if !exists('b:vimshell_variables')
        let b:vimshell_variables = {}
    endif
    if !exists('b:vimshell_system_variables')
        let b:vimshell_system_variables = { 'status' : 0 }
    endif

    " Set environment variables.
    let $TERM = "dumb"
    let $TERMCAP = "COLUMNS=" . winwidth(0)
    let $VIMSHELL = 1
    let $COLUMNS = winwidth(0) * 8 / 10
    let $LINES = winheight(0) * 8 / 10

    call vimshell#print_prompt()

    call vimshell#start_insert()
endfunction"}}}
function! vimshell#switch_shell(split_flag, directory)"{{{
    if &filetype == 'vimshell'
        if winnr('$') != 1
            close
        else
            buffer #
        endif

        if a:directory != ''
            " Change current directory.
            lcd `=fnamemodify(a:directory, ':p')`
            call vimshell#print_prompt()
        endif
        call vimshell#start_insert()
        return
    endif

    " Search VimShell window.
    let l:cnt = 1
    while l:cnt <= winnr('$')
        if getwinvar(l:cnt, '&filetype') == 'vimshell'

            execute l:cnt . 'wincmd w'

            if a:directory != ''
                " Change current directory.
                lcd `=fnamemodify(a:directory, ':p')`
                call vimshell#print_prompt()
            endif
            call vimshell#start_insert()
            return
        endif

        let l:cnt += 1
    endwhile

    " Search VimShell buffer.
    let l:cnt = 1
    while l:cnt <= bufnr('$')
        if getbufvar(l:cnt, '&filetype') == 'vimshell'
            if a:split_flag
                execute 'sbuffer' . l:cnt
                execute 'resize' . winheight(0)*g:VimShell_SplitHeight / 100
            else
                execute 'buffer' . l:cnt
            endif

            if a:directory != ''
                " Change current directory.
                lcd `=fnamemodify(a:directory, ':p')`
                call vimshell#print_prompt()
            endif
            call vimshell#start_insert()
            return
        endif

        let l:cnt += 1
    endwhile

    " Create window.
    call vimshell#create_shell(a:split_flag, a:directory)
endfunction"}}}
function! vimshell#process_enter()"{{{
    if getline('.') !~ vimshell#escape_match(s:prompt)
        " Prompt not found

        if match(getline('$'), vimshell#escape_match(s:prompt)) < 0
            " Create prompt line.
            call append(line('$'), s:prompt)
        endif

        " Search cursor file.
        let l:filename = substitute(substitute(expand('<cfile>'), ' ', '\\ ', 'g'), '\\', '/', 'g')
        if l:filename == '' || (!isdirectory(l:filename) && !filereadable(l:filename))
            return
        endif

        normal! G$
        " Execute cursor file.
        if isdirectory(l:filename)
            call setline(line('$'), s:prompt . l:filename)
        else
            call setline(line('$'), s:prompt . 'vim ' . l:filename)
        endif
    endif

    if line('.') != line('$')
        " History execution.
        if match(getline('$'), vimshell#escape_match(s:prompt)) < 0
            " Insert prompt line.
            call append(line('$'), getline('.'))
        else
            " Set prompt line.
            call setline(line('$'), getline('.'))
        endif
    endif

    " Check current directory.
    if !exists('w:vimshell_directory_stack')
        let w:vimshell_directory_stack = []
    endif

    " Delete prompt string.
    let l:line = substitute(getline('.'), '^' . s:prompt, '', '')

    " Delete comment.
    let l:line = substitute(l:line, '#.*$', '', '')

    if getfsize(g:VimShell_HistoryPath) != s:hist_size
        " Reload.
        let g:vimshell#hist_buffer = readfile(g:VimShell_HistoryPath)
    endif
    " Not append history if starts spaces or dups.
    if l:line !~ '^\s'
        call vimshell#append_history(l:line)
    endif

    " Delete head spaces.
    let l:line = substitute(l:line, '^\s\+', '', '')
    if l:line =~ '^\s*$'
        if g:VimShell_EnableAutoLs
            call setline(line('.'), s:prompt . 'ls')
            call vimshell#execute_internal_command('ls', [], {}, {})

            call vimshell#print_prompt()
            call interactive#highlight_escape_sequence()

            call vimshell#start_insert()
        else
            " Ignore empty command line.
            call setline(line('.'), s:prompt)

            call vimshell#start_insert()
        endif
        return
    elseif l:line =~ '^\s*-\s*$'
        " Popd.
        call vimshell#execute_internal_command('cd', ['-'], {}, {})

        call vimshell#print_prompt()
        call interactive#highlight_escape_sequence()

        call vimshell#start_insert()
        return
    endif

    let l:other_info = { 'has_head_spaces' : l:line =~ '^\s\+', 'is_interactive' : 1, 'is_background' : 0 }
    try
        let l:skip_prompt = vimshell#parser#eval_script(l:line, l:other_info)
    catch /.*/
        call vimshell#error_line({}, v:exception)
        call vimshell#print_prompt()
        call interactive#highlight_escape_sequence()

        call vimshell#start_insert()
        return
    endtry

    if l:skip_prompt
        " Skip prompt.
        return
    endif

    call vimshell#print_prompt()
    call interactive#highlight_escape_sequence()
    call vimshell#start_insert()
endfunction"}}}

function! vimshell#execute_command(program, args, fd, other_info)"{{{
    if empty(a:args)
        let l:line = a:program
    else
        let l:line = printf('%s %s', a:program, join(a:args, ' '))
    endif
    let l:program = a:program
    let l:arguments = a:args
    let l:dir = substitute(substitute(l:line, '^\~\ze[/\\]', substitute($HOME, '\\', '/', 'g'), ''), '\\\(.\)', '\1', 'g')
    let l:command = vimshell#getfilename(program)

    " Special commands.
    if l:line =~ '&\s*$'"{{{
        " Background execution.
        return vimshell#execute_internal_command('bg', split(substitute(l:line, '&\s*$', '', '')), a:fd, a:other_info)
        "}}}
    elseif has_key(g:vimshell#special_func_table, l:program)"{{{
        " Other special commands.
        return call(g:vimshell#special_func_table[l:program], [l:program, l:arguments, a:fd, a:other_info])
        "}}}
    elseif has_key(g:vimshell#internal_func_table, l:program)"{{{
        " Internal commands.

        " Search pipe.
        let l:args = []
        let l:i = 0
        let l:fd = copy(a:fd)
        for arg in l:arguments
            if arg == '|'
                if l:i+1 == len(l:arguments) 
                    call vimshell#error_line(a:fd, 'Wrong pipe used.')
                    return 0
                endif

                " Create temporary file.
                let l:temp = tempname()
                let l:fd.stdout = l:temp
                call writefile([], l:temp)
                break
            endif
            call add(l:args, arg)
            let l:i += 1
        endfor
        let l:ret = call(g:vimshell#internal_func_table[l:program], [l:program, l:args, l:fd, a:other_info])

        if l:i < len(l:arguments)
            " Process pipe.
            let l:prog = l:arguments[l:i + 1]
            let l:fd = copy(a:fd)
            let l:fd.stdin = temp
            let l:ret = vimshell#execute_command(l:prog, l:arguments[l:i+2 :], l:fd, a:other_info)
            call delete(l:temp)
        endif

        return l:ret
        "}}}
    elseif l:command != '' || executable(l:program)
        " Execute external commands.

        " Suffix execution.
        let l:ext = fnamemodify(l:program, ':e')
        if !empty(l:ext) && has_key(g:VimShell_ExecuteFileList, l:ext)
            " Execute file.
            let l:execute = split(g:VimShell_ExecuteFileList[l:ext])[0]
            let l:arguments = extend(split(g:VimShell_ExecuteFileList[l:ext])[1:], insert(l:arguments, l:program))
            return vimshell#execute_command(l:execute, l:arguments, a:fd, a:other_info)
        endif

        " Search pipe.
        let l:args = []
        let l:i = 0
        let l:fd = copy(a:fd)
        for arg in l:arguments
            if arg == '|'
                if l:i+1 == len(l:arguments) 
                    call vimshell#error_line(a:fd, 'Wrong pipe used.')
                    return 0
                endif

                " Check internal command.
                let l:prog = l:arguments[l:i + 1]
                if !has_key(g:vimshell#special_func_table, l:prog) && !has_key(g:vimshell#internal_func_table, l:prog)
                    " Create temporary file.
                    let l:temp = tempname()
                    let l:fd.stdout = l:temp
                    call writefile([], l:temp)
                    break
                endif
            endif
            call add(l:args, arg)
            let l:i += 1
        endfor
        let l:ret = vimshell#execute_internal_command('exe', insert(l:args, l:program), l:fd, a:other_info)

        if l:i < len(l:arguments)
            " Process pipe.
            let l:fd = copy(a:fd)
            let l:fd.stdin = temp
            let l:ret = vimshell#execute_command(l:prog, l:arguments[l:i+2 :], l:fd, a:other_info)
            call delete(l:temp)
        endif

        return l:ret
    elseif isdirectory(l:dir)"{{{
        " Directory.
        " Change the working directory like zsh.

        " Call internal cd command.
        return vimshell#execute_internal_command('cd', [l:dir], a:fd, a:other_info)
        "}}}
    else"{{{
        throw printf('File: "%s" is not found.', l:program)
    endif
    "}}}

    return 0
endfunction"}}}
function! vimshell#execute_internal_command(command, args, fd, other_info)"{{{
    if empty(a:fd)
        let l:fd = { 'stdin' : '', 'stdout' : '', 'stderr' : '' }
    else
        let l:fd = a:fd
    endif

    if empty(a:other_info)
        let l:other_info = { 'has_head_spaces' : 0, 'is_interactive' : 1, 'is_background' : 0 }
    else
        let l:other_info = a:other_info
    endif

    return call('vimshell#internal#' . a:command . '#execute', [a:command, a:args, l:fd, l:other_info])
endfunction"}}}
function! vimshell#read(fd)"{{{
    if empty(a:fd) || a:fd.stdin == ''
        return ''
    endif
    
    if a:fd.stdout == '/dev/null'
        " Nothing.
        return ''
    elseif a:fd.stdout == '/dev/clip'
        " Write to clipboard.
        return @+
    else
        " Read from file.
        if has('win32') || has('win64')
            let l:ff = "\<CR>\<LF>"
        else
            let l:ff = "\<LF>"
            return join(readfile(a:fd.stdin), l:ff) . l:ff
        endif
    endif
endfunction"}}}
function! vimshell#print(fd, string)"{{{
    if a:string == ''
        return
    endif

    if !empty(a:fd) && a:fd.stdout != ''
        if a:fd.stdout == '/dev/null'
            " Nothing.
        elseif a:fd.stdout == '/dev/clip'
            " Write to clipboard.
            let @+ .= a:string
        else
            " Write file.
            let l:file = extend(readfile(a:fd.stdout), split(a:string, '\r\n\|\n'))
            call writefile(l:file, a:fd.stdout)
        endif

        return
    endif

    " Convert encoding for system().
    if has('win32') || has('win64')
        let l:string = iconv(a:string, 'cp932', &encoding) 
    else
        let l:string = iconv(a:string, 'utf-8', &encoding) 
    endif

    " Strip <CR>.
    let l:string = substitute(substitute(l:string, '\r', '', 'g'), '\n$', '', '')
    let l:lines = split(l:string, '\n', 1)
    if line('$') == 1 && empty(getline('$'))
        call setline(line('$'), l:lines[0])
        let l:lines = l:lines[1:]
    endif

    for l:line in l:lines
        call append(line('$'), l:line)
    endfor

    " Set cursor.
    normal! G
endfunction"}}}
function! vimshell#print_line(fd, string)"{{{
    if !empty(a:fd) && a:fd.stdout != ''
        if a:fd.stdout == '/dev/null'
            " Nothing.
        elseif a:fd.stdout == '/dev/clip'
            " Write to clipboard.
            let @+ .= a:string
        else
            " Write file.
            let l:file = add(readfile(a:fd.stdout), a:string)
            call writefile(l:file, a:fd.stdout)
        endif

        return
    elseif line('$') == 1 && empty(getline('$'))
        call setline(line('$'), a:string)
        normal! j
    else
        call append(line('$'), a:string)
        normal! j
    endif
endfunction"}}}
function! vimshell#error_line(fd, string)"{{{
    if !empty(a:fd) && a:fd.stderr != ''
        if a:fd.stderr == '/dev/null'
            " Nothing.
        elseif a:fd.stderr == '/dev/clip'
            " Write to clipboard.
            let @+ .= a:string
        else
            " Write file.
            let l:file = extend(readfile(a:fd.stderr), split(a:string, '\r\n\|\n'))
            call writefile(l:file, a:fd.stderr)
        endif

        return
    endif

    let l:string = '!!! ' . a:string . ' !!!'

    if line('$') == 1 && empty(getline('$'))
        call setline(line('$'), l:string)
        normal! j
    else
        call append(line('$'), l:string)
        normal! j
    endif
endfunction"}}}
function! vimshell#print_prompt()"{{{
    let l:escaped = escape(getline('.'), "\'")
    " Search prompt
    if !exists('b:vimshell_commandline_stack')
        let b:vimshell_commandline_stack = []
    endif
    if empty(b:vimshell_commandline_stack)
        let l:new_prompt = s:prompt
    else
        let l:new_prompt = b:vimshell_commandline_stack[-1]
        call remove(b:vimshell_commandline_stack, -1)
    endif

    if s:user_prompt != ''
        " Insert user prompt line.
        for l:user in split(s:user_prompt, "\\n")
            let l:secondary = '[%] ' . eval(l:user)
            if line('$') == 1 && getline('.') == ''
                call setline(line('$'), l:secondary)
            else
                call append(line('$'), l:secondary)
                normal! j$
            endif
        endfor
    endif

    " Insert prompt line.
    if line('$') == 1 && getline('.') == ''
        call setline(line('$'), l:new_prompt)
    else
        call append(line('$'), l:new_prompt)
        normal! j$
    endif
    let &modified = 0
endfunction"}}}
function! vimshell#append_history(command)"{{{
    " Reduce blanks.
    let l:command = substitute(a:command, '\s\+', ' ', 'g')
    " Filtering.
    call insert(filter(g:vimshell#hist_buffer, printf("v:val != '%s'", substitute(l:command, "'", "''", 'g'))), l:command)

    " Trunk.
    let g:vimshell#hist_buffer = g:vimshell#hist_buffer[:g:VimShell_HistoryMaxSize-1]

    call writefile(g:vimshell#hist_buffer, g:VimShell_HistoryPath)

    let s:hist_size = getfsize(g:VimShell_HistoryPath)
endfunction"}}}
function! vimshell#remove_history(command)"{{{
    " Filtering.
    call filter(g:vimshell#hist_buffer, printf("v:val !~ '^%s\s*'", a:command))

    call writefile(g:vimshell#hist_buffer, g:VimShell_HistoryPath)

    let s:hist_size = getfsize(g:VimShell_HistoryPath)
endfunction"}}}
function! vimshell#getfilename(program)"{{{
    " Command search.
    if has('win32') || has('win64')
        let l:path = substitute($PATH, '\\\?;', ',', 'g')
        let l:files = ''
        for ext in ['', '.bat', '.cmd', '.exe']
            let l:files = globpath(l:path, a:program.ext)
            if !empty(l:files)
                break
            endif
        endfor

        let l:namelist = filter(split(l:files, '\n'), 'executable(v:val)')
    else
        let l:path = substitute($PATH, '/\?:', ',', 'g')
        let l:namelist = filter(split(globpath(l:path, a:program), '\n'), 'executable(v:val)')
    endif

    if empty(l:namelist)
        return ''
    else
        return l:namelist[0]
    endif
endfunction"}}}
function! vimshell#start_insert()"{{{
    " Enter insert mode.
    normal! G$
    startinsert!
    set iminsert=0 imsearch=0
endfunction"}}}
function! vimshell#escape_match(str)"{{{
    return escape(a:str, '~" \.^$[]')
endfunction"}}}
function! vimshell#get_prompt()"{{{
    return s:prompt
endfunction"}}}
function! vimshell#get_secondary_prompt()"{{{
    return s:secondary_prompt
endfunction"}}}
function! vimshell#get_user_prompt()"{{{
    return s:user_prompt
endfunction"}}}
"}}}

function! s:save_current_dir()"{{{
    let l:current_dir = getcwd()
    lcd `=fnamemodify(b:vimshell_save_dir, ':p')`
    let b:vimshell_save_dir = l:current_dir
endfunction"}}}
function! s:restore_current_dir()"{{{
    let l:current_dir = getcwd()
    if l:current_dir != b:vimshell_save_dir
        lcd `=fnamemodify(b:vimshell_save_dir, ':p')`
        let b:vimshell_save_dir = l:current_dir
    endif
endfunction"}}}

augroup VimShellAutoCmd"{{{
    autocmd!
    autocmd BufEnter * if &filetype == 'vimshell' | call s:save_current_dir()
    autocmd BufLeave * if &filetype == 'vimshell' | call s:restore_current_dir()
augroup end"}}}

" vim: foldmethod=marker
