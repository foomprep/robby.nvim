" Yank all lines of current file
function! GetFileContents()
    silent execute 'normal! ggVGy'
    let file_content = @"
    return file_content
endfunction

function! GetCompletion(user_message)
    let json_data = json_encode({
        \ 'model': 'claude-3-5-sonnet-20240620',
        \ 'max_tokens': 1024,
        \ 'system': 'You are an AI programming assistant that updates and edits code as specified the user.  The user will give you a code section and tell you how it needs to be updated or added to, along with additional context.  ONLY return the updated code. and nothing else.',
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

function! GetCodeChanges(prompt)
    let user_message =  "code section:\n" .
        \ GetFileContents() . "\n\n" .
        \ "Changes to be made:\n" .
        \ a:prompt
    let updated_code = GetCompletion(user_message)
    echo updated_code
endfunction

function! Robby(prompt)
    if exists('$ANTHROPIC_API_KEY') && !empty($ANTHROPIC_API_KEY)
        echo GetCodeChanges(a:prompt)
    endif
endfunction

command! -nargs=1 Robby call Robby(<q-args>)
