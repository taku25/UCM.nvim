-- lua/UCM/selector/folder.lua

local conf = require("UCM.conf")
local logger = require("UCM.logger")
local path = require("UCM.path")
local fs = require("vim.fs")

local M = {}

--- Resolves header/source directories, searching up to the module root.
-- @param target_dir string
-- @param module_root string
-- @return string, string: The resolved header_dir and source_dir.
function M.resolve_locations(target_dir, module_root)
  if not target_dir then return "", "" end
  local rules = conf.active_config.folder_rules or {}
  local normalized_target = fs.normalize(target_dir)

  local components = path.split(normalized_target)

  -- 深い階層からコンポーネントをチェック
  for i = #components, 1, -1 do
    local component = components[i]
    for _, rule in ipairs(rules) do
      if component:match(rule.regex) then
        -- マッチした！
        local new_components = vim.deepcopy(components)
        new_components[i] = rule.replacement
        
        -- ★ unpackを使う、あなたが完成させたロジック
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
