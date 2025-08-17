-- lua/UCMUI/ui/new.lua

local frontend = require("UCMUI.frontend")
local api = require("UCM.api")
local logger = require("UCM.logger")

local M = {}

function M.create()
  local collected_opts = {}

  local function ask_for_target_dir()
    frontend.select_code_directory(function(target_dir)
      if not target_dir then
        logger.info("Class creation canceled.")
        return
      end
      collected_opts.target_dir = target_dir
      api.new_class(collected_opts, function(ok, result)
      end)
    end)
  end

  local function ask_for_parent_class()
    local conf = require("UCM.conf")
    local choices = {}
    for _, rule in ipairs(conf.active_config.template_rules) do table.insert(choices, rule.name) end
    local unique_choices = {}; local seen = {}; for _, choice in ipairs(choices) do if not seen[choice] then table.insert(unique_choices, choice); seen[choice] = true end end
    table.sort(unique_choices)

    frontend.select_parent_class(unique_choices, function(selected_parent)
      if not selected_parent then
        logger.info("Class creation canceled.")
        return
      end
      collected_opts.parent_class = selected_parent
      ask_for_target_dir()
    end)
  end

  vim.ui.input({ prompt = "Enter New Class Name:" }, function(class_name)
    if not class_name or class_name == "" then
      logger.info("Class creation canceled.")
      return
    end
    collected_opts.class_name = class_name
    ask_for_parent_class()
  end)
end

return M
