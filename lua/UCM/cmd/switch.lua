-- lua/UCM/cmd/switch.lua

local cmd_core = require("UCM.cmd.core")
local log = require("UCM.logger")

local M = {}

function M.run(opts)
  opts = opts or {}
  local current_file = opts.current_file_path or vim.api.nvim_buf_get_name(0)
  local use_split = opts.has_bang or opts.use_split or false

  cmd_core.resolve_class_pair(current_file, function(class_info, err)
    if not class_info then
      log.get().warn(err or "Failed to resolve class pair.")
      return
    end

    local alternate_path = class_info.is_header_input and class_info.cpp or class_info.h

    if alternate_path then
      vim.schedule(function()
        local open_cmd = use_split and ("vsplit " .. vim.fn.fnameescape(alternate_path))
                                    or ("edit "   .. vim.fn.fnameescape(alternate_path))
        vim.cmd(open_cmd)
      end)
    else
      log.get().warn("Alternate file does not exist for: " .. class_info.class_name)
    end
  end)
end

return M
