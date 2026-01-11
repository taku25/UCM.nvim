-- lua/UCM/api.lua (完全なコード)

local new_cmd = require("UCM.cmd.new")
local delete_cmd = require("UCM.cmd.delete")
local rename_cmd = require("UCM.cmd.rename")
local switch_cmd = require("UCM.cmd.switch")
local move_cmd = require("UCM.cmd.move")
local copy_include_cmd = require("UCM.cmd.copy_include")
local specifiers_cmd = require("UCM.cmd.specifiers")
local copy_imp_cmd = require("UCM.cmd.copy_imp")
local symbols_cmd = require("UCM.cmd.symbols")
local add_struct_cmd = require("UCM.cmd.add_struct")
local create_decl_cmd = require("UCM.cmd.create_decl")
local create_impl_cmd = require("UCM.cmd.create_impl")
local M = {}

-- @param opts table: { class_name, parent_class, target_dir, skip_confirmation = boolean (optional) }
-- @param on_complete function
function M.new_class(opts)
  new_cmd.run(opts)
end

function M.add_struct(opts)
  add_struct_cmd.run(opts)
end

function M.create_declaration()
  create_decl_cmd.execute()
end

function M.create_implementation()
  create_impl_cmd.execute()
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
function M.copy_implementation()
  copy_imp_cmd.execute()
end
function M.specifiers(opts)
  specifiers_cmd.run(opts)
end
function M.symbols(opts)
  symbols_cmd.execute(opts)
end
return M
