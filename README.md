# foomer.nvim
robby is a Lazy plugin for AI assisted coding in Neovim.

## Installation
Add the following plugin file to Neovim config
```robby.lua
return {
    "foomprep/foomer.nvim",
    branch = 'master'
}
```
The plugin currently supports text-based messages for Anthropic and OpenAI models.  To specify which model, set the environment variable `ROBBY_MODEL`
```
export ROBBY_MODEL=claude-3-5-sonnet-20240620
```

> **⚠️ WARNING**
> This plugin generates code and writes directly to the current file, sometimes editing and rewriting the entire file. Make sure that you are using `git` and there are no uncommitted changes.  It's important that you are able to restore all the changes made by robby or you may lose large portions of your work forever. 

## Usage
Open new file
```
touch test & nvim test 
```
To generate code the `TellRobby` command is used.  The `TellRobby` command can be used in both VISUAL and NORMAL modes.  If in VISUAL mode, the command will 
yank whatever lines are highlighted and replace based on prompt.  If in NORMAL mode it will yank all lines in the current buffer and replace them. To start off
generating code from scratch without any context, enter VISUAL mode on empty line and call command
```
:'<,'>TellRobby write your prompt here
```
it will generate code based on the prompt and insert it at the line where cursor is located.

You can also view the history of prompts
```
:History (view history of `AskRobby` using `less` in the editor.
```
