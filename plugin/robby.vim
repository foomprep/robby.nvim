" TODO add support for vscode
" TODO add flag to include other files in context of prompt
" TODO each time code is edited by Robby, automatically commit and use the
" prompt as the commit message, then rewind to last commit using --rewind
" TODO spinner
" TODO Add support for OSX

let g:system_message = { 
    \ "code": "You are an AI programming assistant that updates and edits code as specified the user.  The user will give you a code section and tell you how it needs to be updated or added to, along with additional context. Maintain all identations in the code.  Return the code displayed in between triple backticks.", 
    \ "question": "" 
\ }

let g:help_message = "Robby [options] [prompt]\n\n" .
	\ "If no options are given, Robby will update code according to the " .
	\ "prompt. If the editor is in visual mode when command is run then " .
	\ "the highlighted text is used as context in the prompt, otherwise " .
	\ "the entire file is used as context.  If in visual mode, the highlighted " .
	\ "code is replaced with the updated code, otherwise the ENTIRE " .
	\ "file is edited and rewritten. To generate code with no context, enter visual " .
	\ "on an empty line and then enter prompt normally. \n\n" .
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
function! YankAllLines()
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

let g:spinner_frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
let g:spinner_index = 0
let g:spinner_timer = 0

function! UpdateSpinner(timer)
    let g:spinner_index = (g:spinner_index + 1) % len(g:spinner_frames)
    echo g:spinner_frames[g:spinner_index] . ' Processing...'
    redraw
endfunction

function! StartSpinner()
	echo "StartSpinner"
    let g:spinner_index = 0
    let g:spinner_timer = timer_start(100, UpdateSpinner, {'repeat': -1})
    redraw
endfunction

function! StopSpinner()
    if g:spinner_timer
        call timer_stop(g:spinner_timer)
        let g:spinner_timer = 0
        echo ''
        redraw
    endif
endfunction

function! GetCompletion(user_message, query_type)
    " Start the spinner
    call StartSpinner()

    " TODO add support for ollama and other models
    try
        if match($ROBBY_MODEL, "claude") >= 0
            let result = GetAnthropicCompletion(a:user_message, g:system_message[a:query_type])
        elseif match($ROBBY_MODEL, "gpt") >= 0
            let result = GetOpenAICompletion(a:user_message, g:system_message[a:query_type])
        else
            throw "Model not supported."
        endif
    catch
        " Stop the spinner in case of an error
        call StopSpinner()
        echoerr v:exception
    finally
        " Stop the spinner when the function is done
        call StopSpinner()
    endtry

    return result
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

" TODO if the other window is closed this does not change!
let g:chat_window_num = 0

function! PrintStringToNewChat(str)
	let l:split_string = split(a:str, "\n")
	vsplit
	enew
	let l:buf_num = bufnr('%')
	let g:chat_window_num = winnr()
	echo "Chat window num " . g:chat_window_num
	call setbufline(l:buf_num, line('$'), l:split_string)
	wincmd p
endfunction

function! PrintStringToChat(str)
	let l:split_string = split(a:str, "\n")
	execute g:chat_window_num . 'wincmd w'
	let l:buf_num = bufnr('%') 
	call appendbufline(l:buf_num, line('$'), l:split_string)
	wincmd p
endfunction

function! AskQuestion(user_message)
    let l:completion = GetCompletion(a:user_message, "question")
	let l:n_windows = winnr('$')
	if l:n_windows < 2
		call PrintStringToNewChat(l:completion)		
	else
		call PrintStringToChat(l:completion)
	endif
endfunction

function! GetCodeChanges(prompt, old_code)
    let l:user_message =  "code section:\n" .
        \ a:old_code . "\n\n" .
        \ "Changes to be made:\n" .
        \ a:prompt
    return GetCompletion(l:user_message, "code")
endfunction

" Function to parse arguments from the prompt
function! ParseArguments(prompt)
    let l:args = {}
    let l:args.help = match(a:prompt, "-h") >= 0
    let l:args.question = match(a:prompt, "-q") >= 0
    let l:args.rewind = match(a:prompt, "--rewind") >= 0
    let l:args.commit = match(a:prompt, "-c") >= 0
    let l:args.prompt = a:prompt
    return l:args
endfunction

" Entry point ;)
function! Main(r, line1, line2, prompt)
    let l:args = ParseArguments(a:prompt)

    if l:args.help
        echo g:help_message
        return
    endif

    if l:args.question
        " Check visual mode
        if a:r > 0
            let l:yanked_lines = YankRangeOfLines(a:line1, a:line2)
        else
            let l:yanked_lines = ""
        endif
        let l:user_message = substitute(l:args.prompt, "-q", '', 'g') . "\n\nContext:\n" . l:yanked_lines
		call AskQuestion(l:user_message)
        return
    endif

    if l:args.rewind
        call system("git restore .")
        checktime
        redraw!
        echo "Changes erased space cowboy"
        return
    endif

    if l:args.commit
        let l:commit_msg = substitute(substitute(l:args.prompt, "-c", '', 'g'), '"', '', 'g')
        let l:commit_msg = trim(l:commit_msg)
        let l:cmd = 'Git commit -m "' . l:commit_msg . '"'
        execute 'Git add .'
        execute l:cmd
        echo "Changes committed, space cowboy"
        return
    endif

    if exists('$ROBBY_MODEL') && !empty($ROBBY_MODEL)
        if a:r > 0 
            " In visual mode
            " Yank highlighted text, ask for updates from model
            " and replace highlighted text with update
            " You can enter visual mode without highlighting text
            " to generate without context
            let l:yanked_lines = YankRangeOfLines(a:line1, a:line2)
            let l:new_text = GetCodeChanges(l:args.prompt, l:yanked_lines)
            let l:parsed_text = ExtractCodeBlock(l:new_text)
            if strlen(l:parsed_text) <= 0
                echo l:new_text
            else
                call ReplaceLinesInRange(a:line1, a:line2, l:parsed_text)
            endif
        else 
            " In normal mode
            " This will use all lines of current file and replace
            " entire file by updated code returned by model
            let l:new_text = GetCodeChanges(l:args.prompt, YankAllLines())
            let l:parsed_text = ExtractCodeBlock(l:new_text)
            if strlen(l:parsed_text) <= 0
                echo l:new_text 
            else
                call EraseAndWriteToFile(l:parsed_text) 
            endif
        endif
    else
        echoerr "Env var ROBBY_MODEL must be set"
    endif
endfunction

command! -range -nargs=* Robby call Main(<range>, <line1>, <line2>, <q-args>)
