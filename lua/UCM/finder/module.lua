-- lua/UCM/finder/module.lua
local fs = require("vim.fs")
local core_finder = require("UCM.finder.core")
local M = {}

function M.find(start_path, stop_dir)
  local current_path = fs.normalize(start_path)
  if vim.fn.isdirectory(current_path) ~= 1 then
    current_path =  vim.fn.fnamemodify(current_path, ":h")
  end

  local previous_path = ""
  while current_path and current_path ~= previous_path and current_path:match("[/\\]$") == nil do
    if stop_dir and fs.normalize(current_path) == fs.normalize(stop_dir) then
      break
    end
    
    local build_cs_filename = core_finder.find_file_in_single_dir(current_path, "%.[Bb]uild%.cs$")
    if build_cs_filename then
      local module_name = build_cs_filename:gsub("%.[Bb]uild%.cs$", "")
      return {
        root = current_path,
        name = module_name,
      }
    end
    
    previous_path = current_path
    current_path =  vim.fn.fnamemodify(current_path, ":h")
  end
  return nil
end

return M
