-- lua/UCM/cmd/new.lua (UIフローとコアロジックを統合した最終版)

local unl_picker = require("UNL.backend.picker")
local selectors = require("UCM.selector")
local cmd_core = require("UCM.cmd.core")
local path = require("UCM.path")
local log = require("UCM.logger")
local fs = require("vim.fs")

-- UNLの設定システムからこのプラグイン("UCM")用の設定を取得するヘルパー関数
local function get_config()
  return require("UNL.config").get("UCM")
end

local M = {}

-------------------------------------------------
-- Private Helper Functions
-------------------------------------------------

local function process_template(template_path, replacements)
  if vim.fn.filereadable(template_path) ~= 1 then
    return nil, "Template file not found: " .. template_path
  end
  local ok, lines = pcall(vim.fn.readfile, template_path)
  if not ok then return nil, "Failed to read template: " .. tostring(lines) end
  local content = table.concat(lines, "\n")
  for key, value in pairs(replacements) do
    content = content:gsub("{{" .. key .. "}}", tostring(value or ""))
  end
  return content, nil
end

local function write_file(file_path, content)
  local dir = vim.fn.fnamemodify(file_path, ":h")
  if vim.fn.isdirectory(dir) ~= 1 then vim.fn.mkdir(dir, "p") end
  local ok, file = pcall(io.open, file_path, "w")
  if not ok or not file then return false, "Failed to open file for writing: " .. tostring(file) end
  local write_ok, err = pcall(function() file:write(content) end)
  file:close()
  if not write_ok then return false, "Failed to write to file: " .. tostring(err) end
  return true, nil
end

-------------------------------------------------
-- Main Execution Flow (Core Logic)
-------------------------------------------------

-- この関数が、情報がすべて揃った後に実行されるファイル作成の本体
local function execute_file_creation(opts)
  local conf = get_config()

  -- コールバック関数を定義
  local function on_complete(result)
    log.get().info("Successfully created class: " .. result.class_name)
    log.get().info(" -> Template used: " .. result.template_used)
    log.get().info(" -> Header file: " .. result.header_path)
    log.get().info(" -> Source file: " .. result.source_path)

    local open_setting = conf.auto_open_on_new
    if open_setting == "header" and result.header_path then
      vim.cmd("edit " .. vim.fn.fnameescape(result.header_path))
    elseif open_setting == "source" and result.source_path then
      vim.cmd("edit " .. vim.fn.fnameescape(result.source_path))
    elseif open_setting == "both" and result.header_path and result.source_path then
      vim.cmd("edit " .. vim.fn.fnameescape(result.header_path))
      vim.cmd("vsplit " .. vim.fn.fnameescape(result.source_path))
    end
  end

  local function on_exit(err_msg)
    log.get().error("Operation failed: " .. tostring(err_msg))
  end

  -- Step 1: コンテキストを解決
  local context, err = cmd_core.resolve_creation_context(opts.target_dir)
  if not context then return on_exit(err) end

  -- Step 2: テンプレートを選択
  local template_def = selectors.template.select(opts.parent_class, conf)
  if not template_def then return on_exit("No suitable template found for: " .. opts.parent_class) end

  -- Step 3: テンプレート置換用の情報を準備
  local api_macro = context.module.name:upper() .. "_API"
  local common_replacements = {
    CLASS_NAME = opts.class_name,
    PARENT_CLASS = opts.parent_class,
    API_MACRO = api_macro,
    CLASS_PREFIX = template_def.class_prefix or "U",
    UCLASS_SPECIFIER = template_def.uclass_specifier or "",
    BASE_CLASS_NAME = template_def.base_class_name or opts.parent_class,
  }
  local file_specific_info = {
    header = {
      template_file = template_def.header_template,
      output_dir = context.header_dir,
      output_extension = ".h",
      direct_includes = template_def.direct_includes,
      copyright = conf.copyright_header_h,
    },
    source = {
      template_file = template_def.source_template,
      output_dir = context.source_dir,
      output_extension = ".cpp",
      direct_includes = { string.format('"%s.h"', opts.class_name) },
      copyright = conf.copyright_header_cpp,
    },
  }
  local template_base_path = path.get_template_base_path(template_def, "UCM")
  if not template_base_path then return on_exit("Could not determine template base path.") end

  -- Step 4: テンプレートを処理
  local results = { template_used = template_def.name, class_name = opts.class_name }
  for file_type, info in pairs(file_specific_info) do
    local replacements = vim.deepcopy(common_replacements)
    local includes_str = ""
    if info.direct_includes and #info.direct_includes > 0 then
      includes_str = "#include " .. table.concat(info.direct_includes, "\n#include ")
    end
    replacements.DIRECT_INCLUDES = includes_str
    replacements.COPYRIGHT_HEADER = info.copyright

    local template_path = fs.joinpath(template_base_path, info.template_file)
    local content, template_err = process_template(template_path, replacements)
    if not content then return on_exit(template_err) end
    results[file_type] = {
      path = fs.joinpath(info.output_dir, opts.class_name .. info.output_extension),
      content = content,
    }
  end
  results.header_path = results.header.path
  results.source_path = results.source.path

  -- Step 5: ファイル書き込みを実行
  if vim.fn.filereadable(results.header.path) == 1 or vim.fn.filereadable(results.source.path) == 1 then
    return on_exit("One or both class files already exist.")
  end
  local ok_h, err_h = write_file(results.header.path, results.header.content)
  if not ok_h then return on_exit("Failed to write header file: " .. err_h) end

  local ok_s, err_s = write_file(results.source.path, results.source.content)
  if not ok_s then
    pcall(os.remove, results.header.path) -- クリーンアップ
    return on_exit("Failed to write source file: " .. err_s)
  end

  on_complete(results) -- 成功
end

-------------------------------------------------
-- Public API (Dispatcher)
-------------------------------------------------

--- @param opts table: コマンドビルダーから渡される引数 { class_name?, parent_class?, target_dir? }
function M.run(opts)
  opts = opts or {}

  -- Case 1: 引数が揃っている -> ダイレクト実行
  if opts.class_name and opts.parent_class then
    log.get().debug("Direct mode: UCM new")
    local final_opts = {
      class_name = opts.class_name,
      parent_class = opts.parent_class,
      target_dir = opts.target_dir or vim.loop.cwd(),
    }
    -- ダイレクト実行では確認UIは表示しない
    local conf = get_config()
    if not conf.confirm_on_new then
        final_opts.skip_confirmation = true
    end
    execute_file_creation(final_opts)
    return
  end

  -- Case 2: 引数が足りない -> 対話的UIフローを開始
  log.get().debug("UI mode: UCM new")
  local base_dir = opts.target_dir or vim.loop.cwd()
  
  local collected_opts = {}

  -- UI Flow Step 2: 親クラスを選択
  local function ask_for_parent_class()
    local conf = get_config()
    local choices = {}
    local seen = {}
    for _, rule in ipairs(conf.template_rules) do
      local name = rule.base_class_name or rule.name
      if not seen[name] then
        table.insert(choices, { value = name, label = name })
        seen[name] = true
      end
    end
    table.sort(choices, function(a, b)
      return a.label < b.label
    end)

    unl_picker.pick({
      kind = "ucm_project_parent_class_no_preview",
      title = "  Select Parent Class",
      items = choices,
      conf = conf,
      logger_name = "UCM",
      preview_enabled = false,
      on_submit = function(selected)
        if not selected then return log.get().info("Class creation canceled.") end
        collected_opts.parent_class = selected
        
        if not conf.confirm_on_new then
          execute_file_creation(collected_opts)
        else
          local prompt = ("Create class '%s' with parent '%s'?"):format(collected_opts.class_name, collected_opts.parent_class)
          
          -- ★ 変更点: vim.ui.confirm の代わりに vim.ui.select を使用
          local yes_choice = "Yes, create files"
          vim.ui.select({ yes_choice, "No, cancel" }, { prompt = prompt }, function(choice)
            if choice == yes_choice then
              execute_file_creation(collected_opts)
            else
              log.get().info("Class creation canceled.")
            end
          end)
        end
      end,
    })
  end

  local function ask_for_class_name_and_path()
    vim.ui.input({ prompt = "Enter Class Name (e.g., MyClass or path/to/MyClass):" }, function(user_input)
      if not user_input or user_input == "" then
        return log.get().info("Class creation canceled.")
      end

      -- 入力からパス部分とクラス名部分を分離
      local sanitized_input = user_input:gsub("\\", "/") -- Windowsのパス区切り文字を正規化
      local class_name = vim.fn.fnamemodify(sanitized_input, ":t")
      local subdir_path = vim.fn.fnamemodify(sanitized_input, ":h")

      collected_opts.class_name = class_name

      -- パスが入力されたかどうかでtarget_dirを決定
      if subdir_path == "." or subdir_path == "" then
        -- パスが入力されなかった場合 (例: "MyClass")
        -- -> 起点のディレクトリをそのまま使う
        collected_opts.target_dir = base_dir
      else
        -- パスが入力された場合 (例: "Player/MyPlayerController")
        -- -> 起点のディレクトリと入力されたパスを結合する
        collected_opts.target_dir = vim.fs.joinpath(base_dir, subdir_path)
      end

      log.get().debug("Validating target directory: %s", collected_opts.target_dir)
      local context, err = cmd_core.resolve_creation_context(collected_opts.target_dir)

      if not context then
        -- resolve_creation_contextが失敗した場合、その場所はモジュール内ではない
        -- エラーメッセージを表示して処理を中断する
        log.get().error(err)
        return
      end
      -- 次のステップ（親クラス選択）へ
      ask_for_parent_class()
    end)
  end

  ask_for_class_name_and_path()
end

return M
