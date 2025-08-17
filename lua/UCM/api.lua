-- lua/UCM/api.lua (完全なコード)

local new_cmd = require("UCM.cmd.new")
local delete_cmd = require("UCM.cmd.delete")
local rename_cmd = require("UCM.cmd.rename")
local switch_cmd = require("UCM.cmd.switch")

local M = {}

-- @param opts table: { class_name, parent_class, target_dir, skip_confirmation = boolean (optional) }
-- @param on_complete function
function M.new_class(opts, on_complete)
  new_cmd.run(opts, on_complete) 
end

function M.delete_class(opts, on_complete)
  delete_cmd.run(opts, on_complete)
end

function M.rename_class(opts, on_complete)
  rename_cmd.run(opts, on_complete)
end

-- `switch` はUIを使わないので同期のまま
function M.switch_file(opts)
  return switch_cmd.run(opts)
end

return M
