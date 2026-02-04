-- lua/UCM/api.lua
-- UCM (Unreal Class Manager) Public API

local cmd_new = require("UCM.cmd.new")
local cmd_new_class = require("UCM.cmd.new_class")
local cmd_new_struct = require("UCM.cmd.new_struct")
local cmd_add_struct = require("UCM.cmd.add_struct")
local cmd_delete = require("UCM.cmd.delete")
local cmd_rename = require("UCM.cmd.rename")
local cmd_move = require("UCM.cmd.move")
local cmd_switch = require("UCM.cmd.switch")
local cmd_copy_include = require("UCM.cmd.copy_include")
local cmd_create_decl = require("UCM.cmd.create_decl")
local cmd_create_impl = require("UCM.cmd.create_impl")
local cmd_copy_imp = require("UCM.cmd.copy_imp")
local cmd_specifiers = require("UCM.cmd.specifiers")
local cmd_symbols = require("UCM.cmd.symbols")

local M = {}

--- Create a new class or struct, interactively if args are omitted.
-- @param opts table|nil { name, parent, target_dir }
function M.new(opts)
  cmd_new.run(opts)
end

--- Create a new class, interactively if args are omitted.
-- @param opts table|nil { class_name, parent_class, target_dir }
function M.new_class(opts)
  cmd_new_class.run(opts)
end

--- Create a new struct, interactively if args are omitted.
-- @param opts table|nil { struct_name, parent_struct, target_dir }
function M.new_struct(opts)
  cmd_new_struct.run(opts)
end

--- Insert a new USTRUCT definition at cursor.
-- @param opts table|nil
function M.add_struct(opts)
  cmd_add_struct.run(opts)
end

--- Create function declaration in header from implementation in source.
function M.create_declaration()
  cmd_create_decl.execute()
end
M.create_decl = M.create_declaration

--- Create function implementation in source from declaration in header.
function M.create_implementation()
  cmd_create_impl.execute()
end
M.create_impl = M.create_implementation

--- Delete a class or file, interactively if file path is omitted.
-- @param opts table|nil { file_path }
function M.delete_class(opts)
  cmd_delete.run(opts)
end

--- Rename a class, interactively if args are omitted.
-- @param opts table|nil { file_path, new_class_name }
function M.rename_class(opts)
  cmd_rename.run(opts)
end

--- Move a class/file to another directory.
-- @param opts table|nil { file_path, target_dir }
function M.move_class(opts)
  cmd_move.run(opts)
end

--- Switch between header (.h) and source (.cpp) file.
-- @param opts table|nil { current_file_path }
function M.switch_file(opts)
  cmd_switch.run(opts)
end

--- Copy #include path for current file or selected class.
-- @param opts table|nil { file_path, has_bang }
function M.copy_include(opts)
  cmd_copy_include.run(opts)
end

--- Copy C++ implementation code for the current declaration to clipboard.
function M.copy_implementation()
  cmd_copy_imp.execute()
end

--- Insert Macro Specifiers (UPROPERTY, UFUNCTION, etc).
-- @param opts table|nil { has_bang }
function M.specifiers(opts)
  cmd_specifiers.run(opts)
end

--- Show symbols (functions/properties) in the current file.
-- @param opts table|nil { file_path }
function M.symbols(opts)
  cmd_symbols.execute(opts)
end

return M