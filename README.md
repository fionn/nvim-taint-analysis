# Taint Analysis

> [!NOTE]
> Very much a work in progress.

Tree-sitter based taint analysis in Neovim.

## Features

* [x] Identify definitions and assignments
* [x] Identify sources recursively
* [x] Identify sinks recursively
* [ ] Identify non-assignments (e.g. returns and conditionals)
* [ ] Identify assignments in ranges
* [ ] Identify out-of-scope definitions
* [ ] Identify tainted arguments of functions that aren't assigned
* [ ] Identify values of functions with directly tainted arguments
* [ ] Configurable highlights and keybindings

## Language Support

* [x] Go
* [ ] Lua
* [ ] ...

## Usage

On a symbol, hit <kbd>T</kbd> to find where the symbol is defined and assigned to as well as the scope it is defined in.

Clear the highlights with `:TaintClear`.
