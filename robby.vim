function! IsVisualMode(cmd_string)
    return match(a:cmd_string, "'<,'>")
endfunction

function! YankRangeOfLines(start_line, end_line)
    " Save the current register setting and cursor position
    let save_reg = getreg('"')
    let save_cursor = getpos('.')

    " Move to the start line of the range
    execute 'normal! ' . a:start_line . 'G'

    " Enter visual mode and select the range of lines
    execute "normal! V" . (a:end_line - a:start_line) . "j"

    " Yank the selected lines into register 'a'
    execute "normal! \"ay"

    " Store the yanked text into a variable
    let yanked_text = @a

    " Restore the original register setting and cursor position
    call setreg('"', save_reg)
    call setpos('.', save_cursor)

    " Return the yanked text
    return yanked_text
endfunction

function! ReplaceLinesInRange(start_line, end_line, new_text)
    " Save the current register setting and cursor position
    let save_reg = getreg('"')
    let save_cursor = getpos('.')

    " Move to the start line of the range
    execute 'normal! ' . a:start_line . 'G'

    " Enter visual mode and select the range of lines
    execute "normal! V" . (a:end_line - a:start_line) . "j"

    " Yank the selected lines into register 'a'
    normal! "ay

    " Delete the selected lines
    execute a:start_line . "," . a:end_line . "d"

    " Insert the new text
    call append(a:start_line - 1, split(a:new_text, "\n"))

    " Restore the original register setting and cursor position
    call setreg('"', save_reg)
    call setpos('.', save_cursor)
endfunction

function! ExtractCodeBlock(text)
    " Split the input text into lines
    let lines = split(a:text, "\n")

    " Initialize variables
    let start_line = 0
    let end_line = len(lines) - 1
    let found_start = 0

    " Loop through lines to find the start and end of the code block
    for i in range(len(lines))
        let line = lines[i]
        if found_start == 0
            " Check for the start of the code block
            if line =~ '```'
                let found_start = 1
                let start_line = i + 1
            endif
        else
            " Check for the end of the code block
            if line =~ '```'
                let end_line = i - 1
                break
            endif
        endif
    endfor

    " Return the extracted code block as a string
    if found_start == 1 && start_line <= end_line
        let code_block = join(lines[start_line:end_line], "\n")
        return code_block
    else
        return ""
    endif
endfunction

" Yank all lines of current file
function! GetFileContents()
    silent execute 'normal! ggVGy'
    let file_content = @"
    return file_content
endfunction

function! EraseAndWriteToFile(new_text)
    let save_cursor = getcurpos('.')
    silent execute 'normal! ggVGd'
    call append(0, split(a:new_text, "\n"))
    silent write
    call setpos('.', save_cursor)
endfunction

function! GetCompletion(user_message)
	if match($ROBBY_MODEL, "claude") >= 0
		return GetAnthropicCompletion(a:user_message)
	endif
endfunction



function! GetAnthropicCompletion(user_message)
    let json_data = json_encode({
        \ 'model': 'claude-3-5-sonnet-20240620',
        \ 'max_tokens': 1024,
        \ 'system': 'You are an AI programming assistant that updates and edits code as specified the user.  The user will give you a code section and tell you how it needs to be updated or added to, along with additional context',
        \ 'messages': [
        \   {'role': 'user', 'content': a:user_message}
        \ ]
      \ })

    let escaped_data = substitute(json_data, "'", "'\\\\''", "g")

    let cmd = 'curl -s https://api.anthropic.com/v1/messages ' .
            \ '-H "x-api-key: ' . $ANTHROPIC_API_KEY . '" ' .
            \ '-H "anthropic-version: 2023-06-01" ' .
            \ '-H "content-type: application/json" ' .
            \ "-d '" . escaped_data . "'"
    let result = system(cmd)

    " Check for curl errors
    if v:shell_error
        ec return
    endif

    let response = json_decode(result)
    if has_key(response, 'content') && len(response.content) > 0
        return response.content[0].text
    else
        echoerr "Unexpected response format"
        echo "Response: " . response
        return
    endif
endfunction

function! GetCodeChanges(prompt, old_code)
    let user_message =  "code section:\n" .
        \ a:old_code . "\n\n" .
        \ "Changes to be made:\n" .
        \ a:prompt
    return GetCompletion(user_message)
endfunction

" Entry point ;)
function! Robby(line1, line2, prompt)
	let cmdline_text = @:
    if exists('$ROBBY_MODEL') && !empty($ROBBY_MODEL)
        if IsVisualMode(cmdline_text)
            " Yank highlighted text, ask for updates from model
            " and replace highlighted text with update
            " Save some money babee!
            let yanked_lines = YankRangeOfLines(a:line1, a:line2)
            let new_text = GetCodeChanges(a:prompt, yanked_lines)
            let parsed_text = ExtractCodeBlock(new_text)
            if strlen(parsed_text) <= 0
                echo new_text
            else
                call ReplaceLinesInRange(a:line1, a:line2, parsed_text)
            endif
        else
            " This will use all lines of current file and replace
            " entire file by updated code returned by model
            let new_text = GetCodeChanges(a:prompt, GetFileContents())
            let parsed_text = ExtractCodeBlock(new_text)
            if strlen(parsed_text) <= 0
                echo new_text 
            else
                call EraseAndWriteToFile(parsed_text) 
            endif
        endif
	else
		echoerr "Env var ROBBY_MODEL must be set"
    endif
endfunction

command! -range -nargs=1 Robby call Robby(<line1>, <line2>, <q-args>)
