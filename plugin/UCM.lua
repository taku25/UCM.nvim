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
      handler = function(opts) ucm_api.new_class(opts) end,
      desc = "Create a new class, interactively if args are omitted.",
      args = {
        -- :UCM new MyClass AActor
        { name = "class_name", required = false },
        { name = "parent_class", required = false },
        -- :UCM new MyClass AActor Source/MyModule/Private
        { name = "target_dir", required = false },
      },
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
  },
})
