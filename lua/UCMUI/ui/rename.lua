-- lua/UCMUI/ui/rename.lua

local frontend = require("UCMUI.frontend")
local api = require("UCM.api")
local logger = require("UCM.logger")

local M = {}

function M.create(opts, on_complete)
  opts = opts or {}

  local function start_rename_flow(selected_file)
    local old_name = vim.fn.fnamemodify(selected_file, ":t:r")
    vim.ui.input({ prompt = "Rename: " .. old_name .. " ->", default = old_name }, function(new_name)
      if not new_name or new_name == "" or new_name == old_name then
        return on_complete(false, "canceled")
      end
      api.rename_class({ file_path = selected_file, new_class_name = new_name }, on_complete)
    end)
  end

  if opts.file_path then
    start_rename_flow(opts.file_path)
  else
    frontend.select_cpp_file(function(selected_file)
      if not selected_file then
        return on_complete(false, "canceled")
      end
      start_rename_flow(selected_file)
    end)
  end
end

return M
