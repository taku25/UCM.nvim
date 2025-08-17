-- lua/UCMUI/ui/new.lua

local frontend = require("UCMUI.frontend")
local api = require("UCM.api")
local logger = require("UCM.logger")

local M = {}

local function on_cancel(result, opts)
  --ユーザーのキャンセルも呼ぶ
  logger.info("Operation canceled by user.")
  if opts.on_cancel then
     opts.on_cancel(result)
  end
end


function M.run(opts)
  opts = opts or {}
  local collected_opts = {}

  -- この関数が、すべての情報が集まった後の、共通の処理フロー
  local function start_creation_flow()
    api.new_class(collected_opts, ops)
  end

  local function ask_for_parent_class()
    local conf = require("UCM.conf")
    local choices = {};
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
        return on_cancel("canceled", opts)
      end
      collected_opts.parent_class = selected_parent

      -- すべての情報が集まったので、最終確認＆実行へ
      start_creation_flow()
    end)
  end

  local function ask_for_class_name()
    vim.ui.input({ prompt = "Enter New Class Name:" }, function(class_name)
      if not class_name or class_name == "" then
        return on_cancel("canceled", opts)
      end
      collected_opts.class_name = class_name
      ask_for_parent_class()
    end)
  end

  -- Step 1: まず、ターゲットディレクトリが、すでに与えられているか？
  if opts.target_dir then
    -- もし、Neo-treeなどから、すでにディレクトリが与えられていたら...
    collected_opts.target_dir = opts.target_dir
    collected_opts.skip_confirmation = false -- Neo-treeからでも確認はする
    -- ...ディレクトリ選択UIを、スキップして、クラス名入力へ！
    ask_for_class_name()
  else
    -- そうでなければ、ユーザーにディレクトリを選んでもらう
    frontend.select_code_directory(function(target_dir)
      if not target_dir then
        return on_cancel("canceled", opts)
      end
      collected_opts.target_dir = target_dir
      collected_opts.skip_confirmation = false
      ask_for_class_name()
    end)
  end
end

return M
