-- lua/UCMUI/api.lua (完全なコード)

local new_cmd = require("UCMUI.cmd.new")
local delete_cmd = require("UCMUI.cmd.delete")
local rename_cmd = require("UCMUI.cmd.rename")

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

return M
