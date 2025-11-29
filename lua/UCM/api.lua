-- lua/UCM/api.lua (完全なコード)

local new_cmd = require("UCM.cmd.new")
local delete_cmd = require("UCM.cmd.delete")
local rename_cmd = require("UCM.cmd.rename")
local switch_cmd = require("UCM.cmd.switch")
local move_cmd = require("UCM.cmd.move")
local copy_include_cmd = require("UCM.cmd.copy_include")


local M = {}

-- @param opts table: { class_name, parent_class, target_dir, skip_confirmation = boolean (optional) }
-- @param on_complete function
function M.new_class(opts)
  new_cmd.run(opts)
end

function M.delete_class(opts)
  delete_cmd.run(opts)
end

function M.rename_class(opts)
  rename_cmd.run(opts)
end

function M.move_class(opts)
  move_cmd.run(opts)
end

-- `switch` はUIを使わないので同期のまま
function M.switch_file(opts)
  return switch_cmd.run(opts)
end

function M.copy_include(opts)
  copy_include_cmd.run(opts)
end

return M
