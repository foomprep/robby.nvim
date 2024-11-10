local uv = vim.uv
local os = require("os")
local JSON = require("JSON")
local cjson = require("cjson")

------------ Global variables ---------------------------

local coding_system_message = [[
You are an AI programming assistant that generates code as specified the user.  The user will possibly give you a code section and tell you how it needs to be updated or added to, along with additional context. Maintain all identations in the code. Be concise. Do not include usage examples. Only return the updated code in between triple backticks as in

```
updated code
```

If there is no code section given by the user then simply generate code as specified by the user and return that
generated code between triple backticks.

Maintain all whitespace to the left of each line of previous code, including for the first line.  Do not replace sections of the previous code being edited with comments, such as "// Previous code as before...".

ONLY return the updated code.

]]

local help_message = [[Robby [options] [prompt]

If no options are given, Robby will update code according to the prompt. If the editor is in visual mode when command is run then the highlighted text is used as context in the prompt, otherwise the entire file is used as context.  If in visual mode, the highlighted code is replaced with the updated code, otherwise the ENTIRE file is edited and rewritten. To generate code with no context, enter visual on an empty line and then enter prompt normally. 

options:
		-h 		Help message
		-q		Ask question, prints to buffer, does not change code
		--rewind	Rewind all written unstaged changes
]]

------------------------------------------------------------

----------------------- Utils ----------------------------

local function table2string(o)
	if type(o) == "table" then
		local s = "{ "
		for k, v in pairs(o) do
			if type(k) ~= "number" then
				k = '"' .. k .. '"'
			end
			s = s .. "[" .. k .. "] = " .. table2string(v) .. ","
		end
		return s .. "} "
	else
		return tostring(o)
	end
end

local function create_user_message(context_code, prompt)
	return "code section:\n" .. context_code .. "\n\n" .. "Changes to be made:\n" .. prompt
end

local function create_question_message(context, question)
	return "Question context:\n" .. context .. "\n\n" .. question
end

------------------------------------------------------------

--------------------- Buffer Manip -------------------------
---
local function yank_range_of_lines(start_line, end_line)
	-- Save the current register setting and cursor position
	local save_reg = vim.fn.getreg('"')
	local save_cursor = vim.fn.getpos(".")

	-- Move to the start line of the range
	vim.cmd("normal! " .. start_line .. "G")

	-- Enter visual mode and select the range of lines
	if start_line == end_line then
		vim.cmd("normal! V") -- Select only the current line
	else
		vim.cmd("normal! V" .. (end_line - start_line) .. "j")
	end

	-- Yank the selected lines into register 'a'
	vim.cmd('normal! "ay')

	-- Store the yanked text into a variable
	local yanked_text = vim.fn.getreg("a")

	-- Restore the original register setting and cursor position
	vim.fn.setreg('"', save_reg)
	vim.fn.setpos(".", save_cursor)

	-- Return the yanked text
	return yanked_text
end

---------------------------------------------------------------------

-------------- Spinner ----------------------------------------------
---
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_index = 1
local spinner_timer = nil

local function update_spinner()
	local mode = vim.api.nvim_get_mode().mode
	if mode == "n" then
		-- In normal mode, echo to the command line
		vim.api.nvim_echo({ { spinner_frames[spinner_index], "Normal" } }, false, {})
	elseif mode == "i" then
		-- TODO this doesn't seem to work, investigate
		vim.fn.setcmdline(spinner_frames[spinner_index])
	end
	spinner_index = (spinner_index % #spinner_frames) + 1
end

local function start_spinner()
	if spinner_timer then
		return
	end
	spinner_timer = uv.new_timer()
	spinner_timer:start(
		0,
		100,
		vim.schedule_wrap(function()
			update_spinner()
		end)
	)
end

local function stop_spinner()
	if spinner_timer then
		spinner_timer:stop()
		spinner_timer:close()
		spinner_timer = nil
		vim.api.nvim_echo({ { "", "Fetched" } }, false, {})
	end
end
-------------------------------------------------------------

---------------- Model Stuffs -------------------------------
local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("cjson")

function call_claude_api(system_message, prompt)
	local api_key = os.getenv("ANTHROPIC_API_KEY")
	if not api_key then
		error("ANTHROPIC_API_KEY environment variable not set")
	end

	local request_body = json.encode({
		model = "claude-3-sonnet-20240229",
		max_tokens = 4096,
		system = system_message,
		messages = {
			{
				role = "user",
				content = prompt,
			},
		},
	})

	-- Table to store the response
	local response_body = {}

	-- Set up the request
	local res, code, headers = http.request({
		url = "https://api.anthropic.com/v1/messages",
		method = "POST",
		headers = {
			["Content-Type"] = "application/json",
			["x-api-key"] = api_key,
			["anthropic-version"] = "2023-06-01",
			["Content-Length"] = #request_body,
		},
		source = ltn12.source.string(request_body),
		sink = ltn12.sink.table(response_body),
	})

	-- Check for errors
	if code ~= 200 then
		error("API request failed with code " .. tostring(code) .. ": " .. table.concat(response_body))
	end

	-- Parse and return the response
	local response = json.decode(table.concat(response_body))
	return response.content[1].text
end

function call_openai_api(system_message, prompt)
	-- Get API key from environment variable
	local api_key = os.getenv("OPENAI_API_KEY")
	if not api_key then
		error("OPENAI_API_KEY environment variable not set")
	end

	-- Prepare the request body
	local request_body = json.encode({
		model = "gpt-4o",
		messages = {
			{
				role = "system",
				content = system_message,
			},
			{
				role = "user",
				content = prompt,
			},
		},
	})

	-- Table to store the response
	local response_body = {}

	-- Set up the request
	local res, code, headers = http.request({
		url = "https://api.openai.com/v1/chat/completions",
		method = "POST",
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. api_key,
			["Content-Length"] = #request_body,
		},
		source = ltn12.source.string(request_body),
		sink = ltn12.sink.table(response_body),
	})

	-- Check for errors
	if code ~= 200 then
		error("API request failed with code " .. tostring(code) .. ": " .. table.concat(response_body))
	end

	-- Parse and return the response
	local response = json.decode(table.concat(response_body))
	return response.choices[1].message.content
end

local function reset_cursor_to_leftmost_column()
	-- Get the current window and cursor position
	local current_window = vim.api.nvim_get_current_win()
	local cursor_position = vim.api.nvim_win_get_cursor(current_window)

	-- Reset the cursor to the leftmost column (column 0 in 0-based indexing)
	vim.api.nvim_win_set_cursor(current_window, { cursor_position[1], 0 })
end

function extractCode(input)
	-- Use pattern matching to find code blocks without the language specifier
	local code = input:match("```%w*%s*(.-)```")
	return code or "" -- Return the extracted code or an empty string if none found
end

function write_to_line_number(line_number, new_text)
	-- Check if line_number is valid
	if type(line_number) ~= "number" or line_number < 1 then
		return false, "Invalid line number"
	end

	local buf = vim.api.nvim_get_current_buf()
	local line_count = vim.api.nvim_buf_line_count(buf)

	-- Split the text into lines
	local lines = {}
	for line in (new_text .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(lines, line)
	end

	-- Add empty lines if needed
	if line_number > line_count then
		local empty_lines = {}
		for _ = line_count + 1, line_number do
			table.insert(empty_lines, "")
		end
		vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, empty_lines)
	end

	-- Write the new lines starting at the specified line (0-based index in the API)
	vim.api.nvim_buf_set_lines(buf, line_number - 1, line_number, false, lines)

	return true
end

local function query_model(opts, max_tokens)
	max_tokens = max_tokens or 4096 -- Use the provided max_tokens or default to 4096
	local yanked_lines
	if opts.range == 2 then -- Visual Mode
		yanked_lines = yank_range_of_lines(opts.line1, opts.line2)
		vim.api.nvim_buf_set_lines(0, opts.line1, opts.line2, false, {})
	else -- Yank all lines if not in Visual Mode
		yanked_lines = yank_range_of_lines(1, vim.api.nvim_buf_line_count(0))
		vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
	end
	reset_cursor_to_leftmost_column()

	function matchSubstring(str, substr)
		if str:find(substr) then
			return true
		elseif substr:find(str) then
			return true
		else
			return false
		end
	end

	local model = os.getenv("ROBBY_MODEL")
	if model == nil then
		print("Error: ROBBY_MODEL environment variable not set")
		os.exit(1)
	end
	local user_message = create_user_message(yanked_lines, opts.args)

	if model:find("gpt") then
		local response = call_claude_api(coding_system_message, user_message)
		local code = extractCode(response)
		write_to_line_number(opts.line1, code)
	elseif model:find("claude") then
		call_openai_api(coding_system_message, user_message)
	end
end

------------------------------------------------------------------------

----------------------- User Commands -----------------------------------

vim.api.nvim_create_user_command("TellRobby", function(opts)
	query_model(opts)
end, { nargs = "*", range = true })

--vim.api.nvim_create_user_command("AskRobby", function(opts)
--	local yanked_lines = opts.range == 2 and yank_range_of_lines(opts.line1, opts.line2) or ""
--	local user_message = create_question_message(yanked_lines, opts.args)
--	query_model(user_message, "", opts.line1, opts.line2)
--end, { nargs = "*", range = true })

vim.api.nvim_create_user_command("History", function(opts)
	vim.cmd("terminal less +G .chat_history")
	vim.cmd("startinsert")
end, { nargs = 0 })

--------------------------------------------------------------------------
---
