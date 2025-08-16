-- lua/UCM/cmd/core.lua

local finders = require("UCM.finder")
local selectors = require("UCM.selector")
local logger = require("UCM.logger")
local fs = require("vim.fs")

local M = {}

---
-- (PUBLIC) For 'new' command. Resolves context from a target directory.
-- @param target_dir string: The relative or absolute path to the target directory.
-- @return table|nil, string: A context table or nil and an error message.
function M.resolve_creation_context(target_dir)
  -- Step 1: Get the absolute path using the canonical vim function.
  -- This correctly handles both relative and absolute inputs.
  local absolute_dir = fs.normalize(vim.fn.fnamemodify(target_dir, ":p"))

  -- Step 2: Find module context
  local module_info = finders.module.find(absolute_dir)
  if not module_info then
    return nil, "Could not find a .build.cs to determine module context."
  end

  -- Step 3: Resolve header and source directories
  local header_dir, source_dir = selectors.folder.resolve_locations(absolute_dir, module_info.root)

  return {
    module = module_info,
    header_dir = header_dir,
    source_dir = source_dir,
  }
end

---
-- (PUBLIC) For 'switch', 'delete', 'rename'. Resolves an existing class pair from a file.
-- @param file_path string: The relative or absolute path to the input file.
-- @return table|nil, string: A rich info table or nil and an error message.
function M.resolve_class_pair(file_path)
  -- Step 1: Get the absolute path using the canonical vim function.
  local absolute_file = fs.normalize(vim.fn.fnamemodify(file_path, ":p"))

  if vim.fn.filereadable(absolute_file) ~= 1 then
    return nil, "Input file does not exist: " .. absolute_file
  end

  -- Step 2: Use the creation context resolver to get module and folder info
  local context, err = M.resolve_creation_context(fs.dirname(absolute_file))
  if not context then
    return nil, err
  end

  -- Step 3: Build the result for the specific class
  local class_name = vim.fn.fnamemodify(absolute_file, ":t:r")
  local result = {
    h = fs.normalize(fs.joinpath(context.header_dir, class_name .. ".h")),
    cpp = fs.normalize(fs.joinpath(context.source_dir, class_name .. ".cpp")),
    class_name = class_name,
    is_header_input = absolute_file:match("%.h$") and true or false,
    module = context.module,
  }

  -- Step 4: Check for file existence and nullify if not found
  if vim.fn.filereadable(result.h) ~= 1 then result.h = nil end
  if vim.fn.filereadable(result.cpp) ~= 1 then result.cpp = nil end

  if not result.h and not result.cpp then
    return nil, "Could not resolve any existing class files for: " .. class_name
  end

  return result
end

return M
