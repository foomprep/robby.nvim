local uv = vim.uv
local os = require("os")
local JSON = require("JSON")
local http = require("socket.http")
local ltn12 = require("ltn12")

------------ Global variables ---------------------------

local coding_system_message = [[
You are an AI programming assistant that generates code as specified the user.  The user will possibly give you a code section and tell you how it needs to be updated or added to, along with additional context. Maintain all identations in the code. Be concise. Do not include usage examples. Only return the code as in the following examples
Examples:
python```
for i in range(5):
	print(i)
```
javascript```
for (let i = 0; i < 5; i++) {
    console.log(i);
}
```
]]

local help_message = [[Robby [options] [prompt]

If no options are given, Robby will update code according to the prompt. If the editor is in visual mode when command is run then the highlighted text is used as context in the prompt, otherwise the entire file is used as context.  If in visual mode, the highlighted code is replaced with the updated code, otherwise the ENTIRE file is edited and rewritten. To generate code with no context, enter visual on an empty line and then enter prompt normally. 

options:
		-h 		Help message
		-q		Ask question, prints to buffer, does not change code
		--rewind	Rewind all written unstaged changes
]]

----------------------------------------------------------

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

local function replace_lines_in_range(start_line, end_line, new_text)
	-- Save the current register setting and cursor position
	local save_reg = vim.fn.getreg('"')
	local save_cursor = vim.fn.getpos(".")

	-- Move to the start line of the range
	vim.cmd("normal! " .. start_line .. "G")

	-- Enter visual mode and select the range of lines
	vim.cmd("normal! V" .. (end_line - start_line) .. "j")

	-- Yank the selected lines into register 'a'
	vim.cmd('normal! "ay')

	-- Delete the selected lines
	vim.cmd(start_line .. "," .. end_line .. "d")

	-- Insert the new text
	local new_lines = vim.split(new_text, "\n")
	vim.api.nvim_buf_set_lines(0, start_line - 1, start_line - 1, false, new_lines)

	vim.cmd("write")
	-- Restore the original register setting and cursor position
	vim.fn.setreg('"', save_reg)
	vim.fn.setpos(".", save_cursor)
end
----

-------------- Spinner -----------------------
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
local function extract_code_block(text)
	-- Split the input text into lines
	local lines = vim.split(text, "\n")
	-- Initialize variables
	local start_line = 0
	local end_line = #lines
	local found_start = false

	-- Loop through lines to find the start and end of the code block
	for i, line in ipairs(lines) do
		if not found_start then
			-- Check for the start of the code block
			if line:match("```") then
				found_start = true
				start_line = i + 1
			end
		else
			-- Check for the end of the code block
			if line:match("```") then
				end_line = i - 1
				break
			end
		end
	end

	-- Return the extracted code block as a string
	if found_start and start_line <= end_line then
		local code_block = table.concat(lines, "\n", start_line, end_line)
		return code_block
	else
		return ""
	end
end

-- TODO generalize this so that depending on model used the cmd variable changes
local function generate_curl_command(prompt, system_message, max_tokens)
	local model = os.getenv("ROBBY_MODEL")
	if not model then
		error("ROBBY_MODEL environment variable must be set cowboy!")
	end

	if string.match(model, "claude") then -- Anthropic
		local api_key = os.getenv("ANTHROPIC_API_KEY")
		local body = JSON:encode({
			model = model,
			max_tokens = max_tokens,
			system = system_message,
			messages = {
				{ role = "user", content = prompt },
			},
			stream = true,
		})
		return string.format(
			"curl -s -X POST 'https://api.anthropic.com/v1/messages' "
				.. "-H 'Content-Type: application/json' "
				.. "-H 'X-API-Key: %s' "
				.. "-H 'anthropic-version: 2023-06-01' "
				.. "--data '%s'",
			api_key,
			body:gsub("'", "'\\''") -- Escape single quotes in the body
		)
	elseif string.match(model, "gpt") then -- OpenAI
		local api_key = os.getenv("OPENAI_API_KEY")
		local body = JSON:encode({
			model = model,
			max_tokens = max_tokens,
			messages = {
				{ role = "system", content = system_message },
				{ role = "user", content = prompt },
			},
			stream = stream,
		})
		return string.format(
			"curl --no-buffer -s -X POST 'https://api.openai.com/v1/chat/completions' "
				.. "-H 'Content-Type: application/json' "
				.. "-H 'Authorization: Bearer %s' "
				.. "--data '%s'",
			api_key,
			body:gsub("'", "'\\''") -- Escape single quotes in the body
		)
	elseif string.match(model, "ollama") then -- Ollama
		local ollama_model = string.sub(model, 8)
		local body = JSON:encode({
			model = ollama_model,
			max_tokens = max_tokens,
			messages = {
				{ role = "system", content = system_message },
				{ role = "user", content = prompt },
			},
			stream = false,
		})
		return string.format(
			"curl --no-buffer -s -X POST 'http://localhost:11434/api/chat' "
				.. "-H 'Content-Type: application/json' "
				.. "--data '%s'",
			body:gsub("'", "'\\''") -- Escape single quotes in the body
		)
	end

	return nil
end

local function write_string_at_cursor(str)
	vim.schedule(function()
		local current_window = vim.api.nvim_get_current_win()
		local cursor_position = vim.api.nvim_win_get_cursor(current_window)
		local row, col = cursor_position[1], cursor_position[2]

		local lines = vim.split(str, "\n")

		vim.cmd("undojoin")
		vim.api.nvim_put(lines, "c", true, true)

		local num_lines = #lines
		local last_line_length = #lines[num_lines]
		vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
	end)
end

-- TODO not sure this hack works, is each function guaranteed to be called in the right order?
-- Need to figure out a way to enfore structed generation
local s = ""
local printing = false
local ticks_index = 0
local first_tick = true
local function handle_anthropic_spec_data(data_stream, event_state)
	if event_state == "content_block_delta" then
		local json = JSON:decode(data_stream)
		if json.delta and json.delta.text then
			local start, finish = string.find(json.delta.text, "```", ticks_index)
			if finish then
				if first_tick then
					write_string_at_cursor(string.sub(json.delta.text, finish + 1))
					ticks_index = finish
					first_tick = false
					finish = nil
					printing = true
				else
					write_string_at_cursor(string.sub(json.delta.text, 0, finish - 4))
					ticks_index = 0
					printing = false
					first_tick = true
					finish = nil
				end
			else
				if printing then
					write_string_at_cursor(json.delta.text)
				end
			end
		end
	end
end

local function parse_and_call(line)
	local event = string.match(line, "^event:%s*(.+)$")
	if event then
		curr_event_state = event
		return
	end
	local data_match = string.match(line, "^data: (.+)$")
	if data_match then
		handle_anthropic_spec_data(data_match, curr_event_state)
	end
end

local function parse_response_by_model(result)
	local model = os.getenv("ROBBY_MODEL")
	if model then
		if string.match(model, "claude") then
			return result.content[1].text
		elseif string.match(model, "gpt") then
			return result.choices[1].message.content
		elseif string.match(model, "ollama") then
			return result.message.content
		else
			return nil
		end
	else
		return nil
	end
end

local function query_model(prompt, system_message, line1, line2, max_tokens)
	max_tokens = max_tokens or 4096 -- Use the provided max_tokens or default to 4096

	local cmd = generate_curl_command(prompt, system_message, max_tokens)

	start_spinner()
	local output = ""
	local job_id = vim.fn.jobstart({ "sh", "-c", cmd }, {
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					output = output .. line
				end
			end
		end,
		on_stderr = function(_, data)
			-- Handle stderr data here
			stop_spinner()
			print("Stderr:", vim.inspect(data))
		end,
		on_exit = function(_, exit_code)
			-- Handle job exit here
			print("Job exited with code:", exit_code)
			local decoded = JSON:decode(output)
			local response = parse_response_by_model(decoded)
			if not response then
				vim.api.nvim_echo({ { "ROBBY_MODEL env var not set correctly", "ErrorMsg" } }, false, {})
				return
			end
			if #system_message > 0 then
				local code_change = extract_code_block(response)
				replace_lines_in_range(line1, line2, code_change)
			else
				vim.api.nvim_echo({ { response, "Normal" } }, false, {})

				local file = io.open(".chat_history", "a")
				if file then
					file:write(response .. "\n")
					file:close()
				else
					vim.api.nvim_echo({ { " Failed to write to .chat_history", "ErrorMsg" } }, false, {})
				end
			end
			stop_spinner()
		end,
	})

	if job_id == 0 then
		print("Failed to start job")
	elseif job_id == -1 then
		print("Invalid arguments for jobstart")
	end
end

------------------------------------------------------------------------

----------------------- User Commands -----------------------------------

vim.api.nvim_create_user_command("TellRobby", function(opts)
	if opts.range == 2 then -- Visual Mode
		local yanked_lines = yank_range_of_lines(opts.line1, opts.line2)
		local user_message = create_user_message(yanked_lines, opts.args)
		query_model(user_message, coding_system_message, opts.line1, opts.line2)
	end
end, { nargs = "*", range = true })

vim.api.nvim_create_user_command("AskRobby", function(opts)
	local yanked_lines = opts.range == 2 and yank_range_of_lines(opts.line1, opts.line2) or ""
	local user_message = create_question_message(yanked_lines, opts.args)
	query_model(user_message, "", opts.line1, opts.line2)
end, { nargs = "*", range = true })

vim.api.nvim_create_user_command("Rewind", function(opts)
	vim.fn.system("git restore .")
	vim.cmd("redraw!")
end, { nargs = 0 })

vim.api.nvim_create_user_command("History", function(opts)
	vim.cmd("terminal less +G .chat_history")
	vim.cmd("startinsert")
end, { nargs = 0 })

--------------------------------------------------------------------------

----------------------- Key Mappings -------------------------------------

local function generate_code_from_current_line()
	vim.cmd("stopinsert") -- Exit visual/insert mode
	local current_line = vim.fn.getline(".")
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	-- Escape any quotes in the current line to avoid breaking the command
	current_line = current_line:gsub('"', '\\"')
	local user_message = create_user_message("", current_line)
	query_model(user_message, coding_system_message, line_num, line_num)
end

-- TODO rewrite this so that it checks the type of the current file and uses comments in that language
--vim.keymap.set({ "i", "v", "n" }, "#;", function()
--	generate_code_from_current_line()
--end, { desc = "Generate code from current line" })

--------------------------------------------------------------------------
