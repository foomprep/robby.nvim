function! GetCompletion(prompt)
    let json_data = json_encode({
        \ 'model': 'claude-3-5-sonnet-20240620',
        \ 'max_tokens': 1024,
        \ 'messages': [
        \   {'role': 'user', 'content': a:prompt}
        \ ]
      \ })

    let escaped_data = substitute(json_data, "'", "'\\\\''", "g")

    let cmd = 'curl -s https://api.anthropic.com/v1/messages ' .
            \ '-H "x-api-key: ' . $ANTHROPIC_API_KEY . '" ' .
            \ '-H "anthropic-version: 2023-06-01" ' .
            \ '-H "content-type: application/json" ' .
            \ "-d '" . escaped_data . "'"
    echo cmd
    
    let result = system(cmd)

    " Check for curl errors
    if v:shell_error
        ec    return
    endif

    let response = json_decode(result)
    if has_key(response, 'content') && len(response.content) > 0
        return response.content[0].text
    else
        echoerr "Unexpected response format"
        return
    endif
endfunction

function! GetFileContents()
    silent execute 'normal! ggVGy'
    let file_content = @"
    return file_content
endfunction

function! Robby(prompt)
    if exists('$ANTHROPIC_API_KEY') && !empty($ANTHROPIC_API_KEY)
        echo GetCompletion(a:prompt)
    endif
endfunction

command! -nargs=1 Robby call Robby(<q-args>)
