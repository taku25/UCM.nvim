-- lua/UCM/path.lua

-- This module contains utility functions related to path resolution and manipulation.
local log = require("UCM.logger")

local M = {}

-- Cache table to store the root path for EACH plugin.
-- The key is the plugin name (e.g., "UCM"), the value is the path.
local plugin_root_paths = {}

--- Initializes the path module FOR a specific plugin.
-- This is now safe to be called by multiple plugins (UBT, UCM, etc.).
-- @param plugin_name string (e.g., "UCM", "UBT")
function M.setup(plugin_name)
  -- This function no longer needs to do anything, as the name is passed
  -- to the function that needs it. We can keep it for API consistency
  -- or remove it. Let's keep it for now in case we need it later.
end


--- Finds and returns the root path of a GIVEN plugin.
-- @param plugin_name string The name of the plugin to find.
-- @return string|nil The absolute path to the plugin's root directory, or nil if not found.
function M.get_plugin_root_path(plugin_name)
  if not plugin_name then
    log.get().error("get_plugin_root_path requires a plugin_name.", vim.log.levels.ERROR)
    return nil
  end
  
  if plugin_root_paths[plugin_name] then
    return plugin_root_paths[plugin_name]
  end

  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    if path:match("[/\\]" .. plugin_name .. ".nvim$") then
      plugin_root_paths[plugin_name] = path
      return path
    end
  end
  
  log.get().error("[" .. plugin_name .. "] Could not determine the plugin's root path.", vim.log.levels.WARN)
  return nil
end

--- Gets the base directory path for a given template definition.
-- It now requires the plugin_name to know which plugin's templates to look for.
-- @param template_def table The template definition from the config.
-- @param plugin_name string The name of the plugin context.
-- @return string|nil The base path where the template files are located, or nil on failure.
function M.get_template_base_path(template_def, plugin_name)
  local template_dir = template_def.template_dir or "builtin"

  if template_dir == "builtin" then
    local root = M.get_plugin_root_path(plugin_name)
    if not root then return nil end
    return root .. "/templates"
  else
    return vim.fn.expand(template_dir)
  end
end

--- Splits a path into its directory components.
-- Handles both Windows and Unix-style separators.
-- @param path_str string The path to split.
-- @return table A list of directory names.
function M.split(path_str)
  local components = {}
  -- `gsub`の魔法で、パス区切り文字ではない部分をすべてキャプチャする
  for component in path_str:gmatch("([^/\\]+)") do
    table.insert(components, component)
  end
  return components
end



return M
