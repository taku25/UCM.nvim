# UCM.nvim

# Unreal Class Manager 💓 Neovim

\<table\>
  \<tr\>
   \<td\>\<div align=center\>\<img width="100%" alt="UCM New Class Interactive Demo" src="[https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/main-image-new.png](https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/main-image-new.png)" /\>\</div\>\</td\>
   \<td\>\<div align=center\>\<img width="100%" alt="UCM Rename Class Interactive Demo" src="[https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/main-image-delete.png](https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/main-image-delete.png)" /\>\</div\>\</td\>
  \</tr\>
\</table\>

`UCM.nvim` is a plugin for managing your Unreal Engine C++ classes (creation, file switching, renaming, deletion) from within Neovim.
Your workflow will be enhanced by using it alongside [UBT.nvim](https://github.com/taku25/UBT.nvim) and [UEP.nvim](https://github.com/taku25/UEP.nvim).

[English](https://www.google.com/search?q=./README.md) | [日本語 (Japanese)](https://www.google.com/search?q=./README_ja.md)

-----

## ✨ Features

  * **Data-driven Design**:
      * Centrally manage project-specific complex folder structures (`Public`/`Private`) and diverse class rules in a configuration file.
      * Class creation, renaming, deletion, and switching between source/header files are determined based on these rules.
        **Note: All operations are file-system based. Renaming class symbols within the code should be handled by your LSP.**
  * **UI**:
      * For `new`, `rename`, and `delete` commands, UI frontends like [Telescope](https://github.com/nvim-telescope/telescope.nvim) or [fzf-lua](https://github.com/ibhagwan/fzf-lua) are automatically detected and used.
      * It's also possible to specify one explicitly. If neither is installed, the native Neovim UI is used as a fallback.

\<table\>
  \<tr\>
   \<td\>
   \<div align=center\>
   \<img width="100%" alt="UCM new gif" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/ucmui-new.gif" /\>\<br\>
   \<code\>:UCM new\</code\> command
   \</div\>
   \</td\>
   \<td\>
   \<div align=center\>
   \<img width="100%" alt="UCM rename gif" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/ucmui-rename.gif" /\>\<br\>
   \<code\>:UCM rename\</code\> command
   \</div\>
   \</td\>
  \</tr\>
\</table\>

## 🔧 Requirements

  * Neovim v0.11.3 or higher
  * **Optional (Strongly recommended for an enhanced UI experience):**
      * [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
      * [fzf-lua](https://github.com/ibhagwan/fzf-lua)
      * [fd](https://github.com/sharkdp/fd) (**Required when using `Telescope` or `fzf-lua` UI**)

## 🚀 Installation

Example configuration for [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  'taku25/UCM.nvim',
  dependencies = {
    "taku25/UNL.nvim", -- Required!
    -- Either one
    "nvim-telescope/telescope.nvim", -- optional
    "ibhagwan/fzf-lua", -- optional
  },
  opts = {
    -- Configure as you see fit
  },
}
```

## ⚙️ Configuration

You can customize the plugin's behavior by passing a table to the `opts` field.

```lua
opts = {
  -- Select the UI frontend to use
  -- "auto": Automatically selects in the order of priority: Telescope -> fzf-lua -> native
  -- "telescope": Prioritizes Telescope (requires fd)
  -- "fzf-lua": Prioritizes fzf-lua (requires fd)
  -- "native": Uses the standard vim.ui (fd is not required)
  ui_frontend = "auto",

  -- Whether to show a confirmation UI when running the :UCM new command
  confirm_on_new = true,

  -- Copyright header for new header files
  copyright_header_h = "// Copyright...",
  -- Copyright header for new source files
  copyright_header_cpp = "// Copyright..",

  -- Default parent class for :UCM new when omitted
  default_parent_class = "Actor",

  -- Templates for class creation
  template_rules = {
    {
      name = "Object",
      priority = 0,
      parent_regex = ".*", -- Default for any UObject
      template_dir = "builtin",
      header_template = "UObject.h.tpl",
      source_template = "UObject.cpp.tpl",
      class_prefix = "U",
      uclass_specifier = "",
      base_class_name = "Object",
      direct_includes = { '"UObject/Object.h"' },
    },
  },
  -- Rules for finding the corresponding source/header file
  folder_rules = {
    -- Basic Public <-> Private mapping
    { type = "header",  regex = "^[Pp]ublic$", replacement = "Private" },
    { type = "source",  regex = "^[Pp]rivate$", replacement = "Public" },
    { type = "header",  regex = "^[Cc]lasses$", replacement = "Sources" },
    { type = "source",  regex = "^[Ss]ources$", replacement = "Classes" },
    
    -- Example of an asymmetric rule
    -- { regex = "^Headers$", replacement = "Private" },
    -- { regex = "^Private$", replacement = "Headers" },
  },
}
```

## ⚡ Usage

### 1\. `:UCM`

If no arguments are provided, a UI will be launched.

```viml
:UCM new <ClassName> <ParentClass> [TargetDir] " Directly create a new class
:UCM delete <Relative/Path/To/File>           " Directly delete a class file (extension is optional)
:UCM rename <Relative/Path/To/File> <NewName> " Directly rename a class file (extension is optional)
:UCM move <Source/File/Path> <Target/Dir>    " Move a class to a new directory
:UCM switch                                   " Switch between header/source
```

## 🤖 API & Automation Examples

You can use the `UCM.api` module to integrate with file explorers like `Neo-tree`.
Please check the documentation for all APIs.

```viml
:help ucm
```

### 🌲 Create, delete, and rename classes from Neo-tree

```lua
opts = {
  close_if_last_window  = true,
  -- Example Neo-tree key mapping settings
  filesystem = {
    use_libuv_file_watcher = true,
    window = {
      mappings = {
        ["<leader>n"] = function(state)
          local node = state.tree:get_node()
          require("UCM.api").new_class({ target_dir = node.path })
        end,
        ["<leader>d"] = function(state)
          -- Just pass the path from Neo-tree as an argument!
          local node = state.tree:get_node()
          require("UCM.api").delete_class({ file_path = node.path })
        end,
        ["<leader>r"] = function(state)
          local node = state.tree:get_node()
          require("UCM.api").rename_class({ file_path = node.path })
        end,
      },
    },
  },
},
```

## 📜 License

MIT License

Copyright (c) 2025 taku25

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
