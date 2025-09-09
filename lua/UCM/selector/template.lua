-- lua/UCM/selector/template.lua (priorityを考慮した再帰探索版)

local logger = require("UCM.logger")
local unl_api -- 遅延require用の変数

local M = {}

local function get_parent_class_name(class_name)
  -- (この関数は変更なし)
  if unl_api == nil then
    local ok
    ok, unl_api = pcall(require, "UNL.api")
    if not ok then unl_api = false end
  end
  if not unl_api then return nil end
  local req_ok, header_details = unl_api.provider.request("uep.get_project_classes", { logger_name = "UCM"})
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

-- ★★★ このヘルパー関数を、新しいロジックに書き換えます ★★★
local function select_recursive(class_name, conf, depth)
  depth = depth or 0
  if not class_name or depth > 10 then 
    return nil
  end

  -- Step 1: まず、現在のクラス名で最適なルールを探す
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
  
  -- Step 2: 見つかったルールのpriorityを評価する
  -- priorityが十分に高い（> 10など）か、そもそもルールが見つからなかった場合は再帰しない
  if not best_match_for_current_level or best_match_for_current_level.priority >= 10 then
    if best_match_for_current_level then
      logger.get().info("Found a specific template ('%s') for '%s'. Using this.", best_match_for_current_level.name, class_name)
    end
    -- 最適なルールが見つかった（またはこれ以上探せない）ので、それを返す
    return best_match_for_current_level
  end

  -- Step 3: priorityが低い（< 10）フォールバックルールにマッチした場合、親を辿って探索を続行
  logger.get().info("Matched a generic rule ('%s') for '%s'. Looking for a better match in its parent hierarchy...", best_match_for_current_level.name, class_name)
  local parent_class = get_parent_class_name(class_name)
  
  if parent_class then
    -- 親クラスで再帰的に探索し、もし"より良い"ルールが見つかればそちらを優先する
    local match_from_parent = select_recursive(parent_class, conf, depth + 1)
    if match_from_parent then
      return match_from_parent
    end
  end

  -- 親を辿っても良いルールが見つからなかった場合は、
  -- 最初にマッチした低優先度のルールを最終結果として返す
  logger.get().info("No better match found in parent hierarchy. Using the generic rule '%s'.", best_match_for_current_level.name)
  return best_match_for_current_level
end


function M.select(parent_class, conf)
  -- (公開APIは変更なし、内部ロジックを呼び出すだけ)
  local result = select_recursive(parent_class, conf)
  
  if result then
    return result
  else
    -- どのルールにも（最低優先度のルールすら）マッチしない最悪のケース
    logger.get().warn("Template selection completely failed for '%s'. Falling back to first 'Object' template.", parent_class)
    for _, rule in ipairs(conf.template_rules) do
      if rule.name == "Object" then
        return rule
      end
    end
  end
  
  return nil
end


return M
