-- lua/UCM/finder/uproject.lua
local fs = require("vim.fs")
local core_finder = require("UCM.finder.core")
local M = {}

function M.find_root(start_path)
  local current_path = fs.normalize(start_path)
  if vim.fn.isdirectory(current_path) ~= 1 then
    current_path = fs.dirname(current_path)
  end

  local previous_path = ""
  while current_path and current_path ~= previous_path and current_path:match("[/\\]$") == nil do
    local uproject_filename = core_finder.find_file_in_single_dir(current_path, "%.uproject$")
    if uproject_filename then
      return current_path
    end
    
    previous_path = current_path
    current_path =  vim.fn.fnamemodify(current_path, ":h")
  end
  return nil
end

return M
