-- lua/UCM/cmd/switch.lua

local cmd_core = require("UCM.cmd.core")
local log = require("UCM.logger") -- 変数名を log に変更して統一

local M = {}

function M.run(opts)
  opts = opts or {} 
  local current_file = opts.current_file_path or vim.api.nvim_buf_get_name(0)

  -- Step 1: Resolve the class file pair asynchronously
  cmd_core.resolve_class_pair(current_file, function(class_info, err)
    if not class_info then
      log.get().warn(err or "Failed to resolve class pair.")
      return
    end

    -- Step 2: Determine the path of the alternate file
    local alternate_path = class_info.is_header_input and class_info.cpp or class_info.h

    -- Step 3: Switch to the file if it exists
    if alternate_path then
      vim.schedule(function()
        vim.cmd("edit " .. vim.fn.fnameescape(alternate_path))
      end)
    else
      local err_msg = "Alternate file does not exist for: " .. class_info.class_name
      log.get().warn(err_msg)
    end
  end)
end

return M
