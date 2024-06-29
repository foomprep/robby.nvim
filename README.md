# robby.vim

![alt text](https://github.com/joorjeh/robby/blob/main/robby.png?raw=true)

Robby is a vim plugin that gives you the power to generate and edit code using language models within your vim (or nvim) editor.

## Installation
This plugins relies on commands used in [vim-fugitive](https://github.com/tpope/vim-fugitive).  If you don't already use
`vim-fugitive` please follow the instructions their to install before proceeding.  You should be using `vim-fugitive`.
I repeat, you should be using `vim-fugitive`.

The plugin also assumes you have `curl` installed on your system.

To install you can use your favorite package manager like [vim-plug](https://github.com/junegunn/vim-plug)
or use `vim`'s built-in package support:
```
mkdir -p ~/.vim/pack/robby/start
cd ~/.vim/pack/robby/start
git clone https://github.com/joorjeh/robby.git
```

The plugin currently only supports Anthropic or OpenAI APIs.  To specify which, set the environment variable
`ROBBY_MODEL` with your model of choice.  For example, to use Anthropic's newest Sonnet model:
```
export ROBBY_MODEL=claude-3-5-sonnet-20240620
```
The plugin will only work with text models (or multimodal models that use text).  Any models compatible with 
Anthropic's messages or OpenAI's chat completions endpoints.  The plugin assumes you have the environemnt variables set
for the platform tokens, so either one of these:
```
export OPENAI_API_KEY=<your key>
export ANTHROPIC_API_KEY=<your anthropic_key
```
Open `vim` and run
```
:Robby -q hello
```
to test that your environment is setup correctly and you have credits with your platform of choice.  The `-q` 
tells the plugin to simply query the model for an answer to a question instead of editing the file.

## WARNING!!!  
This plugin generates code and writes directly to the current file, sometimes editing and rewriting the entire file.
Make sure that you are using it to edit/generate code for a project that has `git`. 

The basic workflow is that you generate a new function or make an edit and then either `rewind` the change or commit and 
move incrementally in this way.  `Robby` has a `rewind` command that is just syntactic sugar for `git restore .`.
This is because in many cases the code generation will not work or maybe you didn't prompt correctly, so sometimes you end
up trying something, doesn't work, you rewind with 
```
:Robby --rewind
```
and then try again.  Rinse and repeat.  This project assumes you are working within a git repository.  Disobey at your peril!

## Quickstart
As an example, we'll build a simple python script.  Begin by creating the project and initializing git
```
cd
mkdir my-sample-app && cd my-sample-app
git init
vim substring.py
```
Let's generate a function
```
:Robby Generate a function that counts the number of a substring present in a given string
```
A function should appear in the editor.  Then commit changes
```
:Robby -c "Count function"
```
This command is just wrapper for the lovely plugin `vim-fugitive` by `tpope`.  It stages all changes and then commits them with the given 
message. If you prefer to just `Git` that will work fine. Now, let's change the function a little bit.  Reopen the file and run
```
:Robby add the end argument to the find method as the length of the given string
```
The find method should now change.  Let's say we didn't like this change.  Then we can simply run
```
:Robby --rewind
```
and all unstaged changes will be removed.  Now in each of these changes the entire file is being included in the prompt
and the entire file is being updated by the completion.  Instead, if we only want to update some part of the code that
does not need the rest of file for context, we can use visual mode to highlight the text we want to include in the context.
What is returned by the completion will replace only highlighted text in place.  Go into visual mode and highlight the 
`while` loop in the code.  Then run the editor command (the braces before `Robby` will be added automatically if you are in
visual mode
```
:'<,'>Robby turn this while loop into a for loop
```
When it completes you should see a `for` loop now.  

And that's it!  The last thing to note is that if you want to just insert any generated code without ANY context then
you can go into visual mode wherever you want that code to be written, but not highlight anything.  The plugin will
detect visual mode but not add any context to the prompt.  

## Contributing
AI programming is an interesting new space and contributions are welcome and encouraged.  I'm interested in what seeing people can
do with very simple tools that leverage language models. You can find TODOs by `grep`ing the root directory
```
grep -rnw . -e TODO
```
