# UCM.nvim

# Unreal Class Manager 💓 Neovim

<table>
  <tr>
   <td><div align=center><img width="100%" alt="UCM New Class Interactive Demo" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/main-image-new.png" /></div></td>
   <td><div align=center><img width="100%" alt="UCM Rename Class Interactive Demo" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/main-image-delete.png" /></div></td>
  </tr>
</table>

`UCM.nvim` is a Neovim plugin designed to streamline the management of Unreal Engine C++ classes. It allows you to create, switch, rename, delete, and generate implementation code for C++ classes directly from Neovim, following project-specific rules.

[English](README.md) | [日本語 (Japanese)](README_ja.md)

-----

## ✨ Features

  * **Data-Driven Architecture**:
      * Centrally manage project-specific folder structures (e.g., `Public`/`Private` separation) and class creation rules via `conf.lua`.
      * Class creation, renaming, deletion, and header/source switching are executed based on these robust rules.
      * **Note:** Operations are file-system based. Renaming class symbols within the code should be handled by your LSP.
  * **Seamless UI Integration**:
      * Automatically detects and utilizes [Telescope](https://github.com/nvim-telescope/telescope.nvim) or [fzf-lua](https://github.com/ibhagwan/fzf-lua) as the frontend for `new`, `rename`, and `delete` commands.
      * Falls back to the native Neovim UI if no external UI plugin is installed.
  * **Intelligent Implementation Generation**:
      * The `:UCM copy_imp` command automatically generates the C++ implementation stub for the function declaration under the cursor.
      * It intelligently strips `UFUNCTION` macros, `virtual`/`override` keywords, and default arguments (`= 0.f`), while automatically adding the class scope and `Super::` calls where appropriate.
  * **Smart Includes**:
      * Automatically calculates the correct relative `#include` path (from module `Public` or `Classes` folders) for the current file or a selected class and copies it to the clipboard.
  * **Macro Wizard**:
      * Provides an intelligent completion wizard for Unreal Engine reflection macros (`UPROPERTY`, `UFUNCTION`, etc.).
      * Allows interactive multi-selection of appropriate specifiers (e.g., `EditAnywhere`, `BlueprintReadWrite`) to insert directly into your code.

<table>
  <tr>
   <td>
   <div align=center>
   <img width="100%" alt="UCM new gif" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/ucmui-new.gif" /><br>
   <code>:UCM new</code> Command
   </div>
   </td>
   <td>
   <div align=center>
   <img width="100%" alt="UCM rename gif" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/ucmui-rename.gif" /><br>
   <code>:UCM rename</code> Command
   </div>
   </td>
  </tr>
</table>

## 🔧 Requirements

  * Neovim v0.11.3 or higher
  * [**UNL.nvim**](https://github.com/taku25/UNL.nvim) (**Required**)
  * **Optional (Strongly recommended for an enhanced UI experience):**
      * [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
      * [fzf-lua](https://github.com/ibhagwan/fzf-lua)
      * [fd](https://github.com/sharkdp/fd) (**Required when using `Telescope` or `fzf-lua` UI**)

## 🚀 Installation

Install with your favorite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  'taku25/UCM.nvim',
  dependencies = {
    "taku25/UNL.nvim", -- Required!
    -- Optional UI backends
    "nvim-telescope/telescope.nvim",
    "ibhagwan/fzf-lua",
  },
  opts = {
    -- Configure as you see fit
  },
}
````

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

All commands start with `:UCM`. If no arguments are provided, a UI will be launched.

```viml
" Directly create a new class.
:UCM new <ClassName> <ParentClass> [TargetDir]

" Directly delete a class file (extension is optional).
:UCM delete <Relative/Path/To/File>

" Directly rename a class file (extension is optional).
:UCM rename <Relative/Path/To/File> <NewName>

" Move a class to a new directory.
:UCM move <Source/File/Path> <Target/Dir>

" Switch between the header (.h) and source (.cpp) file.
:UCM switch

" Generates the implementation code for the function declaration under the cursor and copies it to the clipboard.
:UCM copy_imp

" Copy the correct relative #include path for the current file to the clipboard.
:UCM copy_include

" Pick a class from the project list and copy its #include path.
:UCM copy_include!

" Insert specifiers for the current macro context (e.g. UPROPERTY).
:UCM specifiers

" Force open the macro type selector (UPROPERTY/UFUNCTION/etc) and insert specifiers.
:UCM specifiers!
```

## 🤖 API & Automation Examples

You can use the `UCM.api` module to integrate with file explorers like `Neo-tree`.
Please check the documentation for all APIs via `:help ucm`.

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

## Others

**Unreal Engine Related Plugins:**

  * [**UnrealDev.nvim**](https://github.com/taku25/UnrealDev.nvim)
      * **Recommended:** An all-in-one suite to install and manage all these Unreal Engine related plugins at once.
  * [**UNX.nvim**](https://github.com/taku25/UNX.nvim)
      * **Standard:** A dedicated explorer and sidebar optimized for Unreal Engine development. It visualizes project structure, class hierarchies, and profiling insights without depending on external file tree plugins.
  * [UEP.nvim](https://github.com/taku25/UEP.nvim)
      * Analyzes .uproject to simplify file navigation.
  * [UEA.nvim](https://github.com/taku25/UEA.nvim)
      * Finds Blueprint usages of C++ classes.
  * [UBT.nvim](https://github.com/taku25/UBT.nvim)
      * Use Build, GenerateClangDataBase, etc., asynchronously from Neovim.
  * [UCM.nvim](https://github.com/taku25/UCM.nvim)
      * Add or delete classes from Neovim.
  * [ULG.nvim](https://github.com/taku25/ULG.nvim)
      * View UE logs, LiveCoding, stat fps, etc., from Neovim.
  * [USH.nvim](https://github.com/taku25/USH.nvim)
      * Interact with ushell from Neovim.
  * [USX.nvim](https://github.com/taku25/USX.nvim)
      * Plugin for highlight settings for tree-sitter-unreal-cpp and tree-sitter-unreal-shader.
  * [neo-tree-unl](https://github.com/taku25/neo-tree-unl.nvim)
      * Integration for [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) users to display an IDE-like project explorer.
  * [tree-sitter for Unreal Engine](https://github.com/taku25/tree-sitter-unreal-cpp)
      * Provides syntax highlighting using tree-sitter, including UCLASS, etc.
  * [tree-sitter for Unreal Engine Shader](https://github.com/taku25/tree-sitter-unreal-shader)
      * Provides syntax highlighting for Unreal Shaders like .usf, .ush.

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
