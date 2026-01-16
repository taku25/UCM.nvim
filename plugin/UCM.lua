-- plugin/ucm.lua (UNL.command.builderによるコマンド定義)

local builder = require("UNL.command.builder")
local ucm_api = require("UCM.api")

-- :UCMコマンドの定義
builder.create({
  plugin_name = "UCM",
  cmd_name = "UCM",
  desc = "UCM: Unreal Class Manager commands", -- コマンドの説明

  subcommands = {
    ["new"] = {
      handler = function(opts) ucm_api.new(opts) end,
      desc = "Create a new class or struct, interactively if args are omitted.",
      args = {
        { name = "name", required = false },
        { name = "parent", required = false },
        { name = "target_dir", required = false },
      },
    },
    ["new_class"] = {
      handler = function(opts) ucm_api.new_class(opts) end,
      desc = "Create a new class, interactively if args are omitted.",
      args = {
        { name = "class_name", required = false },
        { name = "parent_class", required = false },
        { name = "target_dir", required = false },
      },
    },

    ["new_struct"] = {
      handler = function(opts) ucm_api.new_struct(opts) end,
      desc = "Create a new struct, interactively if args are omitted.",
      args = {
        -- :UCM new_struct MyStruct FTableRowBase
        { name = "struct_name", required = false },
        { name = "parent_struct", required = false },
        -- :UCM new_struct MyStruct FTableRowBase Source/MyModule/Private
        { name = "target_dir", required = false },
      },
    },

    ["add_struct"] = {
      handler = function(opts) ucm_api.add_struct(opts) end,
      desc = "Insert a new USTRUCT definition at cursor.",
      args = {},
    },

    ["create_decl"] = {
      handler = function(opts) ucm_api.create_declaration() end,
      desc = "Create declaration in header from implementation in source.",
      args = {},
    },

    ["create_impl"] = {
      handler = function(opts) ucm_api.create_implementation() end,
      desc = "Create implementation in source from declaration in header.",
      args = {},
    },

    ["delete"] = {
      handler = function(opts) ucm_api.delete_class(opts) end,
      desc = "Delete a class, interactively if file path is omitted.",
      args = {
        -- :UCM delete Source/MyModule/Public/MyClass.h
        { name = "file_path", required = false },
      },
    },

    ["move"] = {
      handler = function(opts) ucm_api.move_class(opts) end,
      desc = "Move a class, interactively if file path is omitted.",
      args = {
        -- :UCM delete Source/MyModule/Public/MyClass.h
        { name = "file_path ", required = false },
        { name = "target_dir ", required = false },
      },
    },

    ["rename"] = {
      handler = function(opts) ucm_api.rename_class(opts) end,
      desc = "Rename a class, interactively if args are omitted.",
      args = {
        -- :UCM rename Source/MyModule/Public/MyClass.h MyNewClassName
        { name = "file_path", required = false },
        { name = "new_class_name", required = false },
      },
    },

    ["switch"] = {
      handler = function()
        -- switchは常に現在のバッファを対象とするため引数なし
        local current_file = vim.api.nvim_buf_get_name(0)
        if current_file and current_file ~= "" then
          ucm_api.switch_file({ current_file_path = current_file })
        else
          require("UCM.logger").get().warn("No file open in current buffer to switch.")
        end
      end,
      desc = "Switch between header and source file.",
      -- このコマンドは引数を取らない
      args = {},
    },

    ["copy_include"] = {
      handler = function(opts) ucm_api.copy_include(opts) end,
      bang = true,
      desc = "Copy #include path for current file or selected class (!).",
      args = { { name = "file_path", required = false } },
    },
    ["specifiers"] = {
      handler = function(opts) ucm_api.specifiers(opts) end,
      bang = true, -- ! をつけるとマクロタイプを強制選択
      desc = "Insert Macro Specifiers (UPROPERTY, UFUNCTION, etc). Use '!' to force select macro type.",
      args = {},
    },
    ["copy_imp"] = {
      handler = function() ucm_api.copy_implementation() end,
      desc = "UCM: Copy C++ implementation code for the current declaration.",
      args = {},
    },
    ["symbols"] = {
      handler = function(opts) ucm_api.symbols(opts) end,
      desc = "Show symbols (functions/properties) in the current file.",
      args = { { name = "file_path", required = false } },
    },
  },
})
