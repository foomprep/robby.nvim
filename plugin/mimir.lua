local os = require("os")

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
	if not code then
		return ""
	end

	-- Remove leading/trailing whitespace and newlines
	code = code:gsub("^%s*[\n\r]*", "") -- Remove leading whitespace/newlines
	code = code:gsub("%s*[\n\r]*$", "") -- Remove trailing whitespace/newlines
	return code
end

-- TODO figure out why newlines are being added to result in Normal mode
function write_to_line_number(line_number, new_text)
	-- Check if line_number is valid
	if type(line_number) ~= "number" or line_number < 1 then
		return false, "Invalid line number"
	end
	local buf = vim.api.nvim_get_current_buf()
	local line_count = vim.api.nvim_buf_line_count(buf)
	-- Split the text into lines
	local lines = {}
	for line in new_text:gmatch("[^\n]+") do
		table.insert(lines, line)
	end
	-- Add empty lines if needed
	if line_number > line_count then
		local empty_lines = {}
		for i = line_count + 1, line_number do
			table.insert(empty_lines, "")
		end
		vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, empty_lines)
	end
	-- Write the new lines starting at the specified line (0-based index in the API)
	vim.api.nvim_buf_set_lines(buf, line_number - 1, line_number, false, lines)

	-- Remove any leading empty lines
	local buffer_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local first_non_empty = 0
	for i, line in ipairs(buffer_lines) do
		if line ~= "" then
			first_non_empty = i - 1
			break
		end
	end
	if first_non_empty > 0 then
		vim.api.nvim_buf_set_lines(buf, 0, first_non_empty, false, {})
	end

	return true
end

---------------------------------------------------------------------

-------------- Spinner ----------------------------------------------
---
local uv = vim.uv

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
local json = require("cjson")
local Job = require("plenary.job")

function call_claude_api(system_message, prompt, insert_line)
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

	local response_body = {}

	-- Use plenary's Job to execute a curl command
	Job:new({
		command = "curl",
		args = {
			"-X",
			"POST",
			"-H",
			"Content-Type: application/json",
			"-H",
			"x-api-key: " .. api_key,
			"-H",
			"anthropic-version: 2023-06-01",
			"-d",
			request_body,
			"https://api.anthropic.com/v1/messages",
		},
		on_exit = function(job, return_val)
			if return_val ~= 0 then
				error("API request failed with code " .. tostring(return_val))
			else
				local result = table.concat(job:result(), "\n")
				local response = json.decode(result)
				local code = extractCode(response.content[1].text)
				vim.schedule(function()
					print("Fin!")
					stop_spinner()
					write_to_line_number(insert_line, code)
				end)
			end
		end,
	}):start()
end

function call_openai_api(system_message, prompt, insert_line)
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

	local result = {}

	Job:new({
		command = "curl",
		args = {
			"-X",
			"POST",
			"-H",
			"Content-Type: application/json",
			"-H",
			"Authorization: Bearer " .. api_key,
			"-d",
			request_body,
			"https://api.openai.com/v1/chat/completions",
		},
		on_exit = function(job, return_val)
			if return_val ~= 0 then
				error("API request failed with code " .. tostring(return_val))
			else
				local result = table.concat(job:result(), "\n")
				local response = json.decode(result)
				local content = response.choices[1].message.content
				local code = extractCode(content)
				vim.schedule(function()
					print("Fin!")
					stop_spinner()
					write_to_line_number(insert_line, code)
				end)
			end
		end,
	}):start()
end

function call_fireworks_api(system_message, prompt, insert_line)
	-- Get API key from environment variable
	local api_key = os.getenv("FIREWORKS_API_KEY")
	if not api_key then
		error("FIREWORKS_API_KEY environment variable not set")
	end

	-- Prepare the request body
	local request_body
	if os.getenv("MIMIR_MODEL") then
		request_body = json.encode({
			model = os.getenv("MIMIR_MODEL"),
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
	else
		print("MIMIR_MODEL environment variable is not set. Exiting.")
		return
	end

	local result = {}

	Job:new({
		command = "curl",
		args = {
			"-X",
			"POST",
			"-H",
			"Content-Type: application/json",
			"-H",
			"Authorization: Bearer " .. api_key,
			"-d",
			request_body,
			"https://api.fireworks.ai/inference/v1/chat/completions",
		},
		on_exit = function(job, return_val)
			if return_val ~= 0 then
				error("API request failed with code " .. tostring(return_val))
			else
				local result = table.concat(job:result(), "\n")
				local response = json.decode(result)
				local content = response.choices[1].message.content
				local code = extractCode(content)
				vim.schedule(function()
					print("Fin!")
					stop_spinner()
					write_to_line_number(insert_line, code)
				end)
			end
		end,
	}):start()
end

local function query_model(opts, max_tokens)
	start_spinner()
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

	local model = os.getenv("MIMIR_MODEL")
	if model == nil then
		print("Error: MIMIR_MODEL environment variable not set")
		os.exit(1)
	end
	local user_message = create_user_message(yanked_lines, opts.args)

	if model:find("gpt") then
		call_openai_api(coding_system_message, user_message, opts.line1)
	elseif model:find("claude") then
		call_claude_api(coding_system_message, user_message, opts.line1)
	elseif model:find("fireworks") then
		call_fireworks_api(coding_system_message, user_message, opts.line1)
	end
end

------------------------------------------------------------------------

----------------------- User Commands -----------------------------------

vim.api.nvim_create_user_command("Mim", function(opts)
	query_model(opts)
end, { nargs = "*", range = true })

--vim.api.nvim_create_user_command("AskRobby", function(opts)
--	local yanked_lines = opts.range == 2 and yank_range_of_lines(opts.line1, opts.line2) or ""
--	local user_message = create_question_message(yanked_lines, opts.args)
--	query_model(user_message, "", opts.line1, opts.line2)
--end, { nargs = "*", range = true })

-- TODO make into subcommand like `Mim history`
vim.api.nvim_create_user_command("MimHistory", function(opts)
	vim.cmd("terminal less +G .chat_history")
	vim.cmd("startinsert")
end, { nargs = 0 })

--------------------------------------------------------------------------
---
