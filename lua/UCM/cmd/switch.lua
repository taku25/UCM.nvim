-- lua/UCM/cmd/switch.lua

local cmd_core = require("UCM.cmd.core")
local logger = require("UCM.logger")

local M = {}

function M.run(opts)
  opts = opts or {} 
  opts.current_file_path = opts.current_file_path or vim.api.nvim_buf_get_name(0)

  -- Step 1: Resolve the class file pair from the current buffer path
  local class_info, err = cmd_core.resolve_class_pair(opts.current_file_path)
  if not class_info then
    return false, err
  end

  -- Step 2: Determine the path of the alternate file
  local alternate_path = class_info.is_header_input and class_info.cpp or class_info.h

  -- Step 3: Switch to the file if it exists
  if alternate_path then
    vim.cmd("edit " .. vim.fn.fnameescape(alternate_path))
    return true
  else
    local err_msg = "Alternate file does not exist."
    logger.warn(err_msg)
    return false, err_msg
  end
end

return M
