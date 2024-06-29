" TODO allow visual mode and highlighted text with question option

let g:system_message = { 
    \ "code": "You are an AI programming assistant that updates and edits code as specified the user.  The user will give you a code section and tell you how it needs to be updated or added to, along with additional context. Maintain all identations in the code.  Return the code displayed in between triple backticks.", 
    \ "question": "" 
\ }

let g:help_message = "Robby [options] [prompt]\n\n" .
	\ "If no options are given, Robby will generate code according to the " .
	\ "prompt. If the editor is in visual mode when command is run then " .
	\ "the highlighted text is used as context in the prompt, otherwise " .
	\ "the entire file is used as context.\n\n" .
	\ "options:\n" .
	\ "		-h 		Help message\n" .
	\ "		-q		Ask question, prints to buffer, does not change code\n" .
	\ "		--rewind	Rewind all written unstaged changes\n"

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
    " Save the current cursor position
    let save_cursor = getcurpos()
    
    " Ensure we're at the beginning of the file
    silent! normal! gg

    " Delete all lines in the buffer
    silent! %delete _

    " Split the new text into lines and append them to the buffer
    call setline(1, split(a:new_text, "\n"))

    " Try to save the file
    try
        silent write
    catch
        echohl ErrorMsg
        echomsg "Failed to write to file: " . v:exception
        echohl None
        return
    endtry

    " Restore cursor position, but ensure it's within bounds
    let max_line = line('$')
    let max_col = col([max_line, '$'])
    let save_cursor[1] = min([save_cursor[1], max_line])
    let save_cursor[2] = min([save_cursor[2], max_col])
    call setpos('.', save_cursor)
endfunction

function! GetCompletion(user_message, query_type)
	" TODO add support for ollama and other models
	if match($ROBBY_MODEL, "claude") >= 0
		return GetAnthropicCompletion(a:user_message, g:system_message[a:query_type])
	elseif match($ROBBY_MODEL, "gpt") >= 0
		return GetOpenAICompletion(a:user_message, g:system_message[a:query_type])
	else
		echoerr "Model not supported."
	endif
endfunction

function! GetOpenAICompletion(user_message, system_message)
    " Check if the curl command is available
    if !executable('curl')
        echoerr "Error: curl is not available. Please install curl to use this function."
        return
    endif

    " Prepare the API endpoint and request data
    let l:url = 'https://api.openai.com/v1/chat/completions'
    let l:data = json_encode({
				\ "model": $ROBBY_MODEL,
                \ "max_tokens": 4096,
                \ "temperature": 0,
				\ "messages": [ 
				\ 	{
				\		"role": "system",
				\ 		"content": a:system_message,
				\	},
				\ 	{
				\		"role": "user",
				\		"content": a:user_message,
				\ 	},
			  \ ]
            \ })

    " Construct the curl command
    let l:cmd = 'curl -s -X POST ' . l:url .
                \ ' -H "Content-Type: application/json"' .
                \ ' -H "Authorization: Bearer ' . $OPENAI_API_KEY . '"' .
                \ " -d '" . escape(l:data, "'") . "'"

    " Execute the curl command and capture the output
    let l:result = system(l:cmd)

    " Parse the JSON response
    let l:response = json_decode(l:result)

    " Check for errors in the API response
	" TODO not sure if this err check works
    if has_key(l:response, 'error')
        echoerr "Error from OpenAI API: " . l:response.error.message
        return
    endif

    " Extract and return the generated text
    return l:response.choices[0].message.content
endfunction

function! GetAnthropicCompletion(user_message, system_message)
    let json_data = json_encode({
        \ 'model': $ROBBY_MODEL,
        \ 'max_tokens': 1024,
		\ 'system': a:system_message,
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
    return GetCompletion(user_message, "code")
endfunction

" Entry point ;)
function! Main(r, line1, line2, prompt)
	" Asking a question will cancel all other options
	if match(a:prompt, "-h") >= 0
		echo g:help_message
		return
	endif
	if match(a:prompt, "-q") >= 0
		echo GetCompletion(substitute(a:prompt, "-q", '', 'g'), "question")
    	return
	endif
	if match(a:prompt, "--rewind") >= 0
		call system("git restore .")
		checktime
		redraw!
		echo "Changes erased space cowboy"
		return
	endif
	if match(a:prompt, "-c") >= 0
		let l:commit_msg = substitute(a:prompt, "-c", '', 'g')
		echo l:commit_msg
		Git add .
		Git "commit -m" . l:commit_msg
		echo "Changes commited space cowboy"
		return
	endif
    if exists('$ROBBY_MODEL') && !empty($ROBBY_MODEL)
        if a:r > 0 
			" In visual mode
            " Yank highlighted text, ask for updates from model
            " and replace highlighted text with update
			" You can enter visual mode without highlighting text
			" to generate without context
            let yanked_lines = YankRangeOfLines(a:line1, a:line2)
            let new_text = GetCodeChanges(a:prompt, yanked_lines)
            let parsed_text = ExtractCodeBlock(new_text)
            if strlen(parsed_text) <= 0
                echo new_text
            else
                call ReplaceLinesInRange(a:line1, a:line2, parsed_text)
            endif
        else 
			" In normal mode
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

command! -range -nargs=* Robby call Main(<range>, <line1>, <line2>, <q-args>)
