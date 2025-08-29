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
-- (★新規) Validation Helper Function
-------------------------------------------------
---
-- ファイル作成操作が可能かを事前に検証する
-- @param validation_opts table { header_path, source_path, header_template, source_template }
-- @return boolean, string|nil
local function validate_creation_operation(validation_opts)
  -- 1. 出力先ファイルが既に存在しないか (上書き防止)
  if vim.fn.filereadable(validation_opts.header_path) == 1 or vim.fn.filereadable(validation_opts.source_path) == 1 then
    return false, "One or both class files already exist at the destination."
  end

  -- 2. 出力先ディレクトリの書き込み権限
  for _, dir in ipairs({ fs.dirname(validation_opts.header_path), fs.dirname(validation_opts.source_path) }) do
    local test_file_path = fs.joinpath(dir, ".ucm_write_test")
    local file, err = io.open(test_file_path, "w")
    if not file then
      return false, string.format("Permission denied in destination directory: %s (Reason: %s)", dir, tostring(err))
    end
    file:close()
    pcall(vim.loop.fs_unlink, test_file_path) -- テストファイルを削除
  end

  -- 3. テンプレートファイルが存在し読み取り可能か
  for _, tpl_path in ipairs({ validation_opts.header_template, validation_opts.source_template }) do
    if vim.fn.filereadable(tpl_path) ~= 1 then
      return false, "Template file not found: " .. tpl_path
    end
  end

  return true, nil
end

-------------------------------------------------
-- Main Execution Flow (Core Logic)
-------------------------------------------------

local function execute_file_creation(opts)
  local conf = get_config()

  -- (★新規) 失敗イベントの発行とエラーログをまとめたヘルパー
  local function publish_and_return_error(message)
    unl_events.publish(unl_types.ON_AFTER_NEW_CLASS_FILE, { status = "failed" })
    log.get().error(message)
  end

  -- Step 1: コンテキストとテンプレートを解決
  local context, err = cmd_core.resolve_creation_context(opts.target_dir)
  if not context then return publish_and_return_error(err) end

  local template_def = selectors.template.select(opts.parent_class, conf)
  if not template_def then return publish_and_return_error("No suitable template found for: " .. opts.parent_class) end

  local template_base_path = path.get_template_base_path(template_def, "UCM")
  if not template_base_path then return publish_and_return_error("Could not determine template base path.") end

  -- Step 2: (★修正) ファイルパスとテンプレートパスを事前に計算
  local header_path = fs.joinpath(context.header_dir, opts.class_name .. ".h")
  local source_path = fs.joinpath(context.source_dir, opts.class_name .. ".cpp")
  local header_template_path = fs.joinpath(template_base_path, template_def.header_template)
  local source_template_path = fs.joinpath(template_base_path, template_def.source_template)
  
  -- Step 3: (★新規) すべての事前検証を実行
  local is_valid, validation_err = validate_creation_operation({
    header_path = header_path,
    source_path = source_path,
    header_template = header_template_path,
    source_template = source_template_path,
  })
  if not is_valid then return publish_and_return_error(validation_err) end

  -- Step 4: (★修正) テンプレートを処理してコンテンツを生成
  local replacements = { -- ... (元のコードから共通部分を抽出)
    CLASS_NAME = opts.class_name, PARENT_CLASS = opts.parent_class,
    API_MACRO = context.module.name:upper() .. "_API",
    CLASS_PREFIX = template_def.class_prefix or "U",
    UCLASS_SPECIFIER = template_def.uclass_specifier or "",
    BASE_CLASS_NAME = template_def.base_class_name or opts.parent_class,
  }
  
  local header_content, h_err = process_template(header_template_path, vim.tbl_extend('keep', { COPYRIGHT_HEADER = conf.copyright_header_h, DIRECT_INCLUDES = "#include " .. table.concat(template_def.direct_includes or {}, "\n#include ") }, replacements))
  if not header_content then return publish_and_return_error(h_err) end
  
  local source_content, s_err = process_template(source_template_path, vim.tbl_extend('keep', { COPYRIGHT_HEADER = conf.copyright_header_cpp, DIRECT_INCLUDES = string.format('#include "%s.h"', opts.class_name) }, replacements))
  if not source_content then return publish_and_return_error(s_err) end

  -- Step 5: (★修正) ファイル書き込みを実行
  local ok_h, err_h = write_file(header_path, header_content)
  if not ok_h then return publish_and_return_error("Failed to write header file: " .. err_h) end

  local ok_s, err_s = write_file(source_path, source_content)
  if not ok_s then
    pcall(vim.loop.fs_unlink, header_path) -- クリーンアップ
    return publish_and_return_error("Failed to write source file: " .. err_s)
  end

  -- Step 6: (★修正) 成功イベントを発行し、後処理を行う
  unl_events.publish(unl_types.ON_AFTER_NEW_CLASS_FILE, {
    status = "success",
    header_path = header_path,
    source_path = source_path,
    template_used = template_def.name,
  })

  log.get().info("Successfully created class: " .. opts.class_name)
  -- (auto_open_on_new のロジックはここ)
  local open_setting = conf.auto_open_on_new
  if open_setting == "header" then vim.cmd("edit " .. vim.fn.fnameescape(header_path))
  elseif open_setting == "source" then vim.cmd("edit " .. vim.fn.fnameescape(source_path))
  elseif open_setting == "both" then
    vim.cmd("edit " .. vim.fn.fnameescape(header_path))
    vim.cmd("vsplit " .. vim.fn.fnameescape(source_path))
  end
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
