-- From: C:\Users\taku3\Documents\git\UCM.nvim\lua\UCM\selector\template.lua

local log = require("UCM.logger")
local unl_api -- 遅延require用の変数

local M = {}

-- ▼▼▼ 修正点 1: get_parent_class_name がキャッシュ(class_data_map)を引数で受け取るようにする ▼▼▼
local function get_parent_class_name(class_name, class_data_map)
  -- 1. キャッシュから親クラス名を返す (高速パス)
  if class_data_map and class_data_map[class_name] and class_data_map[class_name].base_class then
    log.get().debug("Found parent class '%s' in cache for '%s'", class_data_map[class_name].base_class, class_name)
    return class_data_map[class_name].base_class
  end
  -- ▲▲▲

  -- (この関数は変更なし)
  if unl_api == nil then
    local ok
    ok, unl_api = pcall(require, "UNL.api")
    if not ok then unl_api = false end
  end
  if not unl_api then return nil end

  -- ▼▼▼ 修正点 2: キャッシュがなかった場合のみ、APIを呼び出す (低速パス) ▼▼▼
  log.get().warn("Cache miss for '%s'. Falling back to slow API call (uep.get_project_classes) to find parent.", class_name)
  local req_ok, header_details = unl_api.provider.request("uep.get_project_classes", { logger_name = "UCM"})
  -- ▲▲▲
  
  if not (req_ok and header_details) then return nil end
  for _, details in pairs(header_details) do
    if details.classes then
      for _, class_info in ipairs(details.classes) do
        if class_info.class_name == class_name then
          return class_info.base_class
        end
      end
    end
  end
  return nil
end

-- ▼▼▼ 修正点 3: select_recursive が class_data_map をリレーする ▼▼▼
local function select_recursive(class_name, conf, depth, class_data_map)
  depth = depth or 0
  if not class_name or depth > 10 then 
    return nil
  end

  -- ( ... Step 1: 最適なルールを探すロジックは変更なし ... )
  local all_templates = conf.template_rules
  local best_match_for_current_level = nil
  local highest_priority = -1
  for _, template_def in ipairs(all_templates) do
    if class_name:match(template_def.parent_regex) then
      if template_def.priority > highest_priority then
        highest_priority = template_def.priority
        best_match_for_current_level = template_def
      end
    end
  end
  
  if not best_match_for_current_level or best_match_for_current_level.priority >= 10 then
    if best_match_for_current_level then
      log.get().info("Found a specific template ('%s') for '%s'. Using this.", best_match_for_current_level.name, class_name)
    end
    return best_match_for_current_level
  end

  log.get().info("Matched a generic rule ('%s') for '%s'. Looking for a better match in its parent hierarchy...", best_match_for_current_level.name, class_name)
  
  -- [!] class_data_map を get_parent_class_name に渡す
  local parent_class = get_parent_class_name(class_name, class_data_map)
  
  if parent_class then
    -- [!] class_data_map を再帰呼び出しに渡す
    local match_from_parent = select_recursive(parent_class, conf, depth + 1, class_data_map)
    if match_from_parent then
      return match_from_parent
    end
  end

  log.get().info("No better match found in parent hierarchy. Using the generic rule '%s'.", best_match_for_current_level.name)
  return best_match_for_current_level
end


-- ▼▼▼ 修正点 4: 公開API 'select' が class_data_map を受け取るようにする ▼▼▼
function M.select(parent_class, conf, class_data_map)
  -- [!] class_data_map を select_recursive に渡す
  local result = select_recursive(parent_class, conf, 0, class_data_map)
  
  if result then
    return result
  else
    -- ( ... フォールバックロジックは変更なし ... )
    log.get().warn("Template selection completely failed for '%s'. Falling back to first 'Object' template.", parent_class)
    for _, rule in ipairs(conf.template_rules) do
      if rule.name == "Object" then
        return rule
      end
    end
  end
  
  return nil
end
-- ▲▲▲

return M
