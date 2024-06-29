# robby.vim

![alt text](https://github.com/joorjeh/robby/blob/main/robby.png?raw=true)

Robby is a vim plugin that gives you the power to generate and edit code within your vim (or nvim) editor.

## Installation
To install you can use your favorte package manager like [vim-plug](https://github.com/junegunn/vim-plug)
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
to test that your environment is setup correctly and you have credits with your platform of choice.

## WARNING!!!  
This plugin generates code and writes directly to the current file, sometimes editing and rewriting the entire file.
Make sure that you are using it to edit/generate code for a project that has version control like `git`.  
The basic workflow is that you generate a new function or make an edit and then either `rewind` the change or commit and 
move incrementally in this way.  `Robby` has a `rewind` command that is just syntactic sugar for `git restore .`.
This is because in many cases the code generation will not work or maybe you didn't prompt correctly, so sometimes you end
up trying something, doesn't work, you rewind with 
```
:Robby --rewind
```
and then try again.  Rinse and repeat.  This project assumes you are working within a git repository.  Disobey at your peril!

## Contributing
AI programming is an interesting new space and contributions are welcome and encouraged.  I'd like to add all kinds of
different features and the project is SUPER alpha.  I'd really just like   You can find TODOs by `grep`ing the root directory.
```
grep -rnw . -e TODO
```
