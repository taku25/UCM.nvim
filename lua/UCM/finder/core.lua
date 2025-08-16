-- lua/UCM/finder/core.lua
local fs = require("vim.fs")
local M = {}

function M.find_file_in_single_dir(dir_path, file_pattern)
  local ok, handle = pcall(vim.loop.fs_scandir, dir_path)
  if not ok or not handle then return nil end

  while true do
    local name, ftype = vim.loop.fs_scandir_next(handle)
    if not name then break end

    if ftype == 'file' and name:match(file_pattern) then
      local full_path = fs.joinpath(dir_path, name)
      if vim.fn.filereadable(full_path) == 1 then
        return name
      end
    end
  end
  return nil
end

return M
