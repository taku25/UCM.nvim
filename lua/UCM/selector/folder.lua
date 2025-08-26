-- lua/UCM/selector/folder.lua

local path = require("UCM.path")
local fs = require("vim.fs")

local function get_config()
  return require("UNL.config").get("UCM")
end
local M = {}

--- Resolves header/source directories, searching up to the module root.
-- @param target_dir string
-- @param module_root string
-- @return string, string: The resolved header_dir and source_dir.
function M.resolve_locations(target_dir)
  if not target_dir then return "", "" end

  -- ★ 変更点: get_config() で最新の設定を取得
  local conf = get_config()
  local rules = conf.folder_rules or {}
  local normalized_target = fs.normalize(target_dir)

  local components = path.split(normalized_target)

  for i = #components, 1, -1 do
    local component = components[i]
    for _, rule in ipairs(rules) do
      if component:match(rule.regex) then
        local new_components = vim.deepcopy(components)
        new_components[i] = rule.replacement
        
        local _unpack = table.unpack or unpack
        local alternate_path = fs.joinpath(_unpack(new_components))

        if rule.type == "header" then
          return normalized_target, alternate_path
        elseif rule.type == "source" then
          return alternate_path, normalized_target
        end
      end
    end
  end

  return normalized_target, normalized_target
end

return M
