-- lua/plugin/UCM.lua

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
local conf = require("UCM.conf")
local ui = {
  new = require("UCMUI.ui.new"),
  delete = require("UCMUI.ui.delete"),
  rename = require("UCMUI.ui.rename"),
}
-- For non-UI commands (:UCM)
local subcommands = {
  ["new"] = { handler = api.new_class, args = { "class_name", "parent_class", "target_dir" }, required_args = 2, usage = ":UCM new <ClassName> <ParentClassName> [TargetDir]" },
  ["delete"] = { handler = api.delete_class, args = { "file_path" }, required_args = 1, usage = ":UCM delete <Relative/Path/To/File>" },
  ["rename"] = { handler = api.rename_class, args = { "file_path", "new_class_name" }, required_args = 2, usage = ":UCM rename <Relative/Path/To/File> <NewClassName>" },
  ["switch"] = { handler = api.switch_file, args = {}, required_args = 0, usage = ":UCM switch" },
}

-- For UI-based commands (:UCMUI)
local ui_subcommands = {
  ["new"] = { handler = ui.new.create, args = {}, required_args = 0, usage = ":UCMUI new" },
  ["delete"] = { handler = ui.delete.create, args = {}, required_args = 0, usage = ":UCMUI delete" }, -- ★ 追加
  ["rename"] = { handler = ui.rename.create, args = {}, required_args = 0, usage = ":UCMUI rename" }, -- ★ 追加}
}

local function final_on_complete_handler(cmd_name, opts)
  return function(ok, result)
    if ok then
      local class_name_for_msg = result.class_name or opts.class_name or ""
      if cmd_name == "new" then
        logger.info("Successfully created class: " .. class_name_for_msg)
        logger.info(" -> Template used: " .. result.template_used)
        logger.info(" -> Header file: " .. result.header_path)
        logger.info(" -> Source file: " .. result.source_path)
        local open_setting = conf.active_config.auto_open_on_new
        if open_setting == "header" and result.header_path then
          vim.cmd("edit " .. vim.fn.fnameescape(result.header_path))
        elseif open_setting == "source" and result.source_path then
          vim.cmd("edit " .. vim.fn.fnameescape(result.source_path))
        elseif open_setting == "both" and result.header_path and result.source_path then
          vim.cmd("edit " .. vim.fn.fnameescape(result.header_path)); vim.cmd("vsplit " .. vim.fn.fnameescape(result.source_path))
        end
      elseif cmd_name == "delete" then
        logger.info("Successfully deleted class files for: " .. class_name_for_msg)
      elseif cmd_name == "rename" then
        logger.info(string.format("Renamed '%s' to '%s'", class_name_for_msg, opts.new_class_name))
      end
    elseif result == "canceled" then
      logger.info("Operation canceled by user.")
    else
      logger.error("Operation failed: " .. tostring(result))
    end
  end
end

----------------------------------------------------------------------
-- Main Command Implementation for :UCM (Non-UI)
----------------------------------------------------------------------
vim.api.nvim_create_user_command("UCM", function(cmd_args)
  local user_fargs = cmd_args.fargs
  local subcommand_name = user_fargs[1]
  if not subcommand_name then
    logger.info("Usage: :UCM <subcommand> ...")
    return
  end

  local cmd_name_lower = subcommand_name:lower()
  local command_def = subcommands[cmd_name_lower]
  if not command_def then
    logger.error("Unknown UCM subcommand: " .. subcommand_name)
    return
  end

  local _unpack = table.unpack or unpack
  local user_args = { _unpack(user_fargs, 2) }
  if #user_args < command_def.required_args then
    logger.error("Missing arguments. Usage: " .. command_def.usage)
    return
  end

  local opts = {}
  for i, arg_name in ipairs(command_def.args) do
    opts[arg_name] = user_args[i]
  end

  logger.info("Executing: " .. cmd_name_lower .. " with opts: " .. vim.inspect(opts))


  -- Asynchronous commands: new, delete, rename
  if cmd_name_lower == "new" or cmd_name_lower == "delete" or cmd_name_lower == "rename" then
    if cmd_name_lower == "new" and not opts.target_dir then
      opts.target_dir = vim.fn.getcwd()
    end

    command_def.handler(opts, final_on_complete_handler(cmd_name_lower, opts))
  else -- Synchronous commands: switch
    if cmd_name_lower == "switch" then
      opts.current_file_path = vim.api.nvim_buf_get_name(0)
      if not opts.current_file_path or opts.current_file_path == "" then
        logger.error("Cannot switch: Not in a file buffer.")
        return
      end
    end

    local ok, result = command_def.handler(opts)
    if not ok then
      logger.error("Operation failed: " .. tostring(result))
    end
  end
end, {
  nargs = "*",
  desc = "UCM: Manage Unreal Engine classes directly.",
  complete = function(arg_lead, cmd_line)
    local parts = vim.split(cmd_line, " ", true)
    if #parts <= 2 then
      return vim.tbl_filter(function(cmd)
        return vim.startswith(cmd, arg_lead)
      end, vim.tbl_keys(subcommands))
    else
      return vim.fn.getcompletion(arg_lead, "file")
    end
  end,
})

----------------------------------------------------------------------
-- Main Command Implementation for :UCMUI (UI-based)
----------------------------------------------------------------------
vim.api.nvim_create_user_command("UCMUI", function(cmd_args)
  local user_fargs = cmd_args.fargs
  local subcommand_name = user_fargs[1]
  if not subcommand_name then logger.info("Usage: :UCMUI <subcommand> ..."); return end

  local cmd_name_lower = subcommand_name:lower()
  local command_def = ui_subcommands[cmd_name_lower]
  if not command_def then logger.error("Unknown UCMUI subcommand: " .. subcommand_name); return end

  command_def.handler(final_on_complete_handler(cmd_name_lower, {}))
end, {
  nargs = "*",
  desc = "UCM: Manage Unreal Engine classes using interactive UI.",
  complete = function(arg_lead, cmd_line)
    return vim.tbl_filter(function(cmd)
      return vim.startswith(cmd, arg_lead)
    end, vim.tbl_keys(ui_subcommands))
  end,
})
