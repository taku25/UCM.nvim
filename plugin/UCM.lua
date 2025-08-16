-- plugin/UCM.lua

-- Guard: Ensure minimum Neovim version
if 1 ~= vim.fn.has "nvim-0.11.3" then
  vim.api.nvim_err_writeln "UCM.nvim requires at least nvim-0.11.3"
  return 
end

-- Guard: Prevent the file from being loaded more than once
if vim.g.loaded_ucm == 1 then
  return
end
vim.g.loaded_ucm = 1

----------------------------------------------------------------------
-- Module Imports
----------------------------------------------------------------------
local api = require("UCM.api")
local logger = require("UCM.logger")

----------------------------------------------------------------------
-- Command Definition Table
----------------------------------------------------------------------
-- This table defines all available subcommands for :UCM.
-- It makes the command dispatcher clean, extensible, and self-documenting.

local subcommands = {
  ["new"] = {
    handler = api.new_class,
    args = { "class_name", "parent_class", "target_dir" },
    required_args = 2,
    usage = ":UCM new <ClassName> <ParentClassName> [TargetDir]",
  },
  ["delete"] = {
    handler = api.delete_class,
    args = { "file_path" },
    required_args = 1,
    usage = ":UCM delete <Relative/Path/To/File.h>",
  },
  ["rename"] = {
    handler = api.rename_class,
    args = { "file_path", "new_class_name" },
    required_args = 2,
    usage = ":UCM rename <Relative/Path/To/File.h> <NewClassName>",
  },
  ["switch"] = {
    handler = api.switch_file,
    args = {},
    required_args = 0,
    usage = ":UCM switch (from a .h or .cpp file buffer)",
  },
}

----------------------------------------------------------------------
-- Main Command Implementation
----------------------------------------------------------------------

vim.api.nvim_create_user_command(
  "UCM",
  function(cmd_args)
    local user_fargs = cmd_args.fargs
    local subcommand_name = user_fargs[1]
    if not subcommand_name then logger.info("Usage: :UCM <subcommand> ..."); return end

    local cmd_name_lower = subcommand_name:lower()
    local command_def = subcommands[cmd_name_lower]
    if not command_def then logger.error("Unknown UCM subcommand: " .. subcommand_name); return end

    local _unpack = table.unpack or unpack
    local user_args = { _unpack(user_fargs, 2) }
    if #user_args < command_def.required_args then logger.error("Missing arguments. Usage: " .. command_def.usage); return end

    local opts = {}
    for i, arg_name in ipairs(command_def.args) do opts[arg_name] = user_args[i] end

    logger.info("Executing: " .. cmd_name_lower .. " with opts: " .. vim.inspect(opts))

    -- ★ `new` を非同期コマンドのグループに移動
    if cmd_name_lower == "new" or cmd_name_lower == "delete" or cmd_name_lower == "rename" then
      -- ASYNCHRONOUS commands with UI callback
      -- 'new' needs a default for target_dir if not provided
      if cmd_name_lower == "new" and not opts.target_dir then
        opts.target_dir = vim.fn.getcwd()
      end
      
      local on_complete_callback = function(ok, result)
        if ok then
          if cmd_name_lower == "new" then
            logger.info("Successfully created class: " .. opts.class_name)
            logger.info(" -> Template used: " .. result.template_used)
            logger.info(" -> Header file: " .. result.header_path)
            logger.info(" -> Source file: " .. result.source_path)
          elseif cmd_name_lower == "delete" then
            logger.info("Successfully deleted class files for: " .. result.class_name)
          elseif cmd_name_lower == "rename" then
            logger.info(string.format("Renamed '%s' to '%s'", result.class_name, opts.new_class_name))
          end
        elseif result == "canceled" then
          logger.info("Operation canceled by user.")
        else
          logger.error("Operation failed: " .. tostring(result))
        end
      end
      command_def.handler(opts, on_complete_callback)

    else
      -- SYNCHRONOUS commands (only 'switch' is left)
      if cmd_name_lower == "switch" then
        opts.current_file_path = vim.api.nvim_buf_get_name(0)
        if not opts.current_file_path or opts.current_file_path == "" then logger.error("Cannot switch: Not in a file buffer."); return end
      end
      
      local ok, result = command_def.handler(opts)
      if not ok then logger.error("Operation failed: " .. tostring(result)) end
    end
  end,
  {
    nargs = "*",
    desc = "UCM: Manage Unreal Engine classes.",
    complete = function(arg_lead, cmd_line)
      local parts = vim.split(cmd_line, " ", true)
      if #parts <= 2 then return vim.tbl_filter(function(cmd) return vim.startswith(cmd, arg_lead) end, vim.tbl_keys(subcommands))
      else return vim.fn.getcompletion(arg_lead, "file") end
    end,
  }
)
