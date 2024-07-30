# robby
robby is an AI coding assistant for neovim that allows for generating code and also making precise changes based on text selection in VISUAL mode.

inspired by [dingllm](https://github.com/yacineMTB/dingllm.nvim/blob/master/README.md), check it out!

[robby.webm](https://github.com/joorjeh/robby/assets/40566439/84a18c65-fe8c-42d0-b596-5c5d29fba9ec)

## Installation
If using `lazy.nvim` requires no config and can be added to lazy simply by creating file in `plugin` folder`
```
return {
    "joorjeh/robby"
}
```
You can also install by directly downloading
```
mkdir -p ~/.config/nvim/plugin && cd ~/.config/nvim/plugin
git clone https://github.com/joorjeh/robby.git
```
The plugin currently supports text models from Anthropic, OpenAI and ollama.  To specify which, set the environment variable
`ROBBY_MODEL` with your model of choice.  For Anthropic or OpenAI use the model name as is
```
export ROBBY_MODEL=claude-3-5-sonnet-20240620
export ROBBY_MODEL=gpt-4o
```
Relevant api keys should be in the environment for the platform used, such as `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`.
For models hosted locally through `ollama`, prepend the model name by `ollama_` as in 
```
export ROBBY_MODEL=ollama_llama3
```

> **⚠️ WARNING**
> This plugin generates code and writes directly to the current file, sometimes editing and rewriting the entire file. Make sure that you are using `git` and there are no uncommitted changes.  It's important that you are able to restore all the changes made by robby or you may lose large portions of your work forever. 

## Usage
Open new file
```
touch test & nvim test 
```
To generate code from scratch (without any context) you can use the `TellRobby` command.  It only works in VISUAL mode, but if you go to an empty line and enter VISUAL MODE without selecting text, then run 
```
:'<,'>TellRobby write your prompt here
```
it will generate code based on the prompt and insert it at the line where you ran the command.  The plugin command run using `uv` so
you can fire off commands and then go to other parts of your code if you like while it is running.

`TellRobby` will yank whatever text is selected in VISUAL mode and include it as context to the prompt.  The system message for the
model query assumes that you are trying to update or edit code but it can be pretty versatile in terms of generation.  I frequently 
highlight a function(s) and will give some prompt saying how to change it and it works magically!  Or I will prompt the model
to generate a new function given some other one. 

There are also some helper user commands
```
:AskRobby write your question here (query the model with any question but do not insert code changes, only output to `stdout`)
:History (view history of `AskRobby` using `less` in the editor.
```
## Fin
![alt text](https://github.com/joorjeh/robby/blob/main/robby.png?raw=true)
