-- lua/UCMUI/ui/new.lua

local frontend = require("UCMUI.frontend")
local api = require("UCM.api")
local logger = require("UCM.logger")

local M = {}

-- create関数は、pluginレイヤーから、最終処理を行うための on_complete コールバックを受け取る
function M.create(on_complete)
  local collected_opts = {}

  local function ask_for_target_dir()
    frontend.select_code_directory(function(target_dir)
      if not target_dir then
        logger.info("Class creation canceled.")
        return on_complete(false, "canceled") -- ここでも、伝言係を呼ぶ
      end
      collected_opts.target_dir = target_dir

      collected_opts.skip_confirmation = true
      -- apiに、pluginレイヤーから預かった、伝言係を、そのまま渡す
      api.new_class(collected_opts, on_complete)
    end)
  end

  local function ask_for_parent_class()
    local conf = require("UCM.conf")
    local choices = {}
    for _, rule in ipairs(conf.active_config.template_rules) do
      table.insert(choices, rule.name)
    end
    local unique_choices = {}
    local seen = {}
    for _, choice in ipairs(choices) do
      if not seen[choice] then
        table.insert(unique_choices, choice)
        seen[choice] = true
      end
    end
    table.sort(unique_choices)
    frontend.select_parent_class(unique_choices, function(selected_parent)
      if not selected_parent then
        logger.info("Class creation canceled.")
        return on_complete(false, "canceled") -- ここでも、伝言係を呼ぶ
      end
      collected_opts.parent_class = selected_parent
      ask_for_target_dir()
    end)
  end

  vim.ui.input({ prompt = "Enter New Class Name:" }, function(class_name)
    if not class_name or class_name == "" then
      logger.info("Class creation canceled.")
      return on_complete(false, "canceled") -- ここでも、伝言係を呼ぶ
    end
    collected_opts.class_name = class_name
    ask_for_parent_class()
  end)
end

return M
