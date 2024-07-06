# robby the robot (an AI coding assistant for nvim)

## Installation
To install, either download directly into `nvim` config
```
mkdir -p ~/.config/nvim/plugin && cd ~/.config/nvim/plugin
git clone https://github.com/joorjeh/robby.git
```
or you can use `vim-plug`.  Your `init.vim` would look like this
```
call plug#begin()

Plug 'joorjeh/robby'
// Possibly other packages

call plug#end()

lua << EOF
require('robby')
EOF
```
This plugin is not configured to work with `lazy.nvim`.  Personally I spent a few hours trying to setup `lazy` and
it just doesn't seem worth it.  You can always download directly per above if package managers don't work.

The plugin currently only supports Anthropic or OpenAI APIs.  To specify which, set the environment variable
`ROBBY_MODEL` with your model of choice.  For example, to use Anthropic's current Sonnet model:
```
export ROBBY_MODEL=claude-3-5-sonnet-20240620
```
or OpenAI's new model
```
export ROBBY_MODEL=gpt-4o
```
Relevant api keys should be in the environment for the platform used, such as `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`.

> **⚠️ WARNING**
> This plugin generates code and writes directly to the current file, sometimes editing and rewriting the entire file. Make sure that you are using `git` and there are no uncommitted changes.  It's important that you are able to restore all the changes made by robby or you may lose large portions of your work forever. 

## Usage
Open new file
```
touch test & nvim test 
```
To generate code from scratch (without any context) there are two options, first you can generate code inline using the key
mapping `#;` on a line with the prompt.  For example,
```
Generate a function to find all primes up to n #;
```
when you type in `#;` at the end in INSERT mode it will disappear and the plugin will generate code based on the text of the line
and then inject that code at the same line, replacing it.  The other way to generate from scratch is the user command `TellRobby`.
It only works in VISUAL mode, but if you go to an empty line and enter VISUAL MODE without selecting text, then run 
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
If you like this plugin please consider sharing it :)

![alt text](https://github.com/joorjeh/robby/blob/main/robby.png?raw=true)
