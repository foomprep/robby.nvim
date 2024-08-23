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

ONLY return the updated code.
]]

local help_message = [[Robby [options] [prompt]

If no options are given, Robby will update code according to the prompt. If the editor is in visual mode when command is run then the highlighted text is used as context in the prompt, otherwise the entire file is used as context.  If in visual mode, the highlighted code is replaced with the updated code, otherwise the ENTIRE file is edited and rewritten. To generate code with no context, enter visual on an empty line and then enter prompt normally. 

options:
		-h 		Help message
		-q		Ask question, prints to buffer, does not change code
		--rewind	Rewind all written unstaged changes
]]

----------------------------------------------------------

-------------------- Window Setup ------------------------
---

local function open_window_with_git_files()
	-- Run the Git command and capture the output
	local result = vim.fn.system("git ls-files --cached --others --exclude-standard")

	-- Split the result into lines
	local files = vim.split(result, "\n")

	-- Remove the last empty line caused by the trailing newline character
	if files[#files] == "" then
		table.remove(files, #files)
	end

	-- Add an empty checkmark to each file
	for i, file in ipairs(files) do
		files[i] = "[ ] " .. file
	end

	-- Create a new scratch buffer
	local buf = vim.api.nvim_create_buf(false, true) -- false means not listed, true means scratch buffer

	vim.api.nvim_buf_set_keymap(
		buf,
		"n",
		"<LeftMouse>",
		"<Cmd>lua OnMouseClick()<CR>",
		{ noremap = true, silent = true }
	)

	-- Set the content of the buffer to the list of files
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, files)

	-- Split the window vertically and set the new buffer to it
	vim.cmd("vsplit new")
	vim.cmd("vertical resize " .. math.floor(vim.o.columns / 3))
	vim.api.nvim_win_set_buf(0, buf) -- 0 refers to the current window
end

function OnMouseClick()
	vim.schedule(function()
		local line_number = vim.api.nvim_win_get_cursor(0)[1] -- Get the current line number
		print("Line clicked: " .. line_number)
	end)
end

local function toggle_checkmark(line)
	-- Get the current line content
	local content = vim.api.nvim_buf_get_lines(0, line, line + 1, false)[0]
	if string.sub(content, 1, 4) == "[ ] " then
		-- Mark as checked
		content = "[x] " .. string.sub(content, 5)
	elseif string.sub(content, 1, 4) == "[x] " then
		-- Mark as unchecked
		content = "[ ] " .. string.sub(content, 5)
	end
	-- Set the updated line content
	vim.api.nvim_buf_set_lines(0, line, line + 1, false, { content })
end

vim.cmd([[
  autocmd VimEnter * cnoreabbrev q qa
  autocmd VimEnter * cnoreabbrev wq wqa
]])

open_window_with_git_files()

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
			stream = true,
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
			stream = true,
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

local function reset_cursor_to_leftmost_column()
	-- Get the current window and cursor position
	local current_window = vim.api.nvim_get_current_win()
	local cursor_position = vim.api.nvim_win_get_cursor(current_window)

	-- Reset the cursor to the leftmost column (column 0 in 0-based indexing)
	vim.api.nvim_win_set_cursor(current_window, { cursor_position[1], 0 })
end

local function countBackticks(str)
	local count = 0
	for i = 1, #str do
		if str:sub(i, i) == "`" then
			count = count + 1
		end
	end
	return count
end

local function get_last_split(str)
	-- Split the string by backticks
	local parts = vim.split(str, "`", { plain = true })

	-- Return the last part from the split
	return parts[#parts]
end

local function query_model(opts, max_tokens)
	max_tokens = max_tokens or 4096 -- Use the provided max_tokens or default to 4096
	start_spinner()
	local yanked_lines
	if opts.range == 2 then -- Visual Mode
		yanked_lines = yank_range_of_lines(opts.line1, opts.line2)
		vim.api.nvim_buf_set_lines(0, opts.line1 - 1, opts.line2, false, {})
	else -- Yank all lines if not in Visual Mode
		yanked_lines = yank_range_of_lines(1, vim.api.nvim_buf_line_count(0))
		vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
	end
	reset_cursor_to_leftmost_column()

	local user_message = create_user_message(yanked_lines, opts.args)
	local cmd = generate_curl_command(user_message, coding_system_message, max_tokens)

	local tickCount = 0
	local firstBackTick = false
	local job_id = vim.fn.jobstart({ "sh", "-c", cmd }, {
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					local jsonString = vim.split(line, "data:")[2]
					local success, result_or_error = pcall(cjson.decode, jsonString)
					if success then
						local partialMessage = result_or_error.choices[1].delta.content
						tickCount = tickCount + countBackticks(partialMessage)
						if tickCount == 3 then
							if firstBackTick then
								break
							else
								firstBackTick = true
								tickCount = 0
								write_string_at_cursor(get_last_split(partialMessage))
							end
						elseif firstBackTick then
							write_string_at_cursor(partialMessage)
						end
					end
				end
			end
		end,
		on_stderr = function(_, data)
			-- Handle stderr data here
			stop_spinner()
			print("Stderr:", vim.inspect(data))
		end,
		on_exit = function(_, exit_code)
			print("Job exited with code:", exit_code)
			stop_spinner()

			-- Save the current file
			vim.cmd("write")

			-- Add current file to git and commit changes
			local filename = vim.api.nvim_buf_get_name(0)
			if filename and filename ~= "" then
				os.execute("git add " .. filename)
				os.execute('git commit -m "' .. table.concat(opts.fargs, " ") .. '"')
			end
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
	query_model(opts)
end, { nargs = "*", range = true })

--vim.api.nvim_create_user_command("AskRobby", function(opts)
--	local yanked_lines = opts.range == 2 and yank_range_of_lines(opts.line1, opts.line2) or ""
--	local user_message = create_question_message(yanked_lines, opts.args)
--	query_model(user_message, "", opts.line1, opts.line2)
--end, { nargs = "*", range = true })

vim.api.nvim_create_user_command("Rewind", function(opts)
	vim.fn.system("git reset --hard HEAD~1")
	vim.cmd("redraw!")
end, { nargs = 0 })

vim.api.nvim_create_user_command("History", function(opts)
	vim.cmd("terminal less +G .chat_history")
	vim.cmd("startinsert")
end, { nargs = 0 })

--------------------------------------------------------------------------
---
