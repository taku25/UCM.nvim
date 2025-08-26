-- lua/UCM/selector/tpl.lua
local logger = require("UCM.logger")

local M = {}

function M.select(parent_class, conf) -- 第2引数で設定テーブルを受け取る
  local all_templates = conf.template_rules
  if not all_templates then
    logger.warn("conf.active_config.template_rules is not defined.")
    return nil
  end

  local best_match = nil
  local highest_priority = -1

  for _, template_def in ipairs(all_templates) do
    if parent_class:match(template_def.parent_regex) then
      if template_def.priority > highest_priority then
        highest_priority = template_def.priority
        best_match = template_def
      end
    end
  end
  
  return best_match
end

return M
