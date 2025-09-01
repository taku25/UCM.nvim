-- lua/UCM/cmd/rename.lua (UIフローとコアロジックを統合)

local unl_picker = require("UNL.backend.picker")
local cmd_core = require("UCM.cmd.core")
local log = require("UCM.logger")
local fs = require("vim.fs")
local unl_events = require("UNL.event.events")
local unl_event_types = require("UNL.event.types")

local function get_config()
  return require("UNL.config").get("UCM")
end

local M = {}

-------------------------------------------------
-- Private Helper Functions
-------------------------------------------------

-- ファイル内のクラス名を置換するヘルパー
local function replace_content_in_file(file_path, old_name, new_name)
  local read_ok, lines = pcall(vim.fn.readfile, file_path)
  if not read_ok then return false, "Failed to read file: " .. tostring(lines) end
  local content = table.concat(lines, "\n")
  -- 単語境界 `\b` を使って、意図しない置換を防ぐ
  content = content:gsub("\b" .. old_name .. "\b", new_name)
  -- .generated.h のインクルードも置換
  content = content:gsub('"' .. old_name .. '%.generated%.h"', '"' .. new_name .. '.generated.h"')
  
  local write_ok, write_err = pcall(vim.fn.writefile, vim.split(content, '\n'), file_path)
  if not write_ok then return false, "Failed to write updated content: " .. tostring(write_err) end
  return true
end

--- (★新規) リネーム操作の事前検証ヘルパー
local function validate_rename_operation(operations)
  for _, op in ipairs(operations) do
    -- 1. リネーム元ファイルの権限チェック
    local src_file, src_err = io.open(op.old, "a")
    if not src_file then
      return false, string.format("Permission denied on source file: %s (Reason: %s)", op.old, tostring(src_err))
    end
    src_file:close()
    -- 2. リネーム先ファイルが既に存在しないか (上書き防止)
    if vim.fn.filereadable(op.new) == 1 or vim.fn.isdirectory(op.new) == 1 then
      return false, string.format("Destination file already exists, rename aborted to prevent overwrite: %s", op.new)
    end
    -- 3. リネーム先ディレクトリの書き込み権限
    local dest_dir = fs.dirname(op.new)
    local test_file_path = fs.joinpath(dest_dir, ".ucm_write_test")
    local file, err = io.open(test_file_path, "w")
    if not file then
      return false, string.format("Permission denied in destination directory: %s (Reason: %s)", dest_dir, tostring(err))
    end
    file:close()
    pcall(vim.loop.fs_unlink, test_file_path)
  end
  return true, nil
end

-------------------------------------------------
-- Main Execution Flow (Core Logic)
-------------------------------------------------

local function execute_file_rename(opts) -- opts = { file_path, new_class_name }
  -- (★新規) 失敗イベント発行ヘルパー
  local function publish_and_return_error(message)
    unl_events.publish(unl_event_types.ON_AFTER_RENAME_CLASS_FILE, { status = "failed" })
    log.get().error(message)
  end

  -- Step 1: クラスペア解決と基本情報準備
  local class_info, err = cmd_core.resolve_class_pair(opts.file_path)
  if not class_info then return publish_and_return_error(err) end

  local old_class_name = class_info.class_name
  local new_class_name = opts.new_class_name
  if old_class_name == new_class_name then return log.get().info("Rename canceled: names are identical.") end

  -- Step 2: リネーム操作リストを作成
  local operations = {}
  local files_to_process = {}
  if class_info.h then table.insert(files_to_process, class_info.h) end
  if class_info.cpp then table.insert(files_to_process, class_info.cpp) end
  if #files_to_process == 0 then return publish_and_return_error("No existing class files found to rename.") end

  for _, old_path in ipairs(files_to_process) do
    local new_path = fs.joinpath(fs.dirname(old_path), new_class_name .. "." .. vim.fn.fnamemodify(old_path, ":e"))
    table.insert(operations, { old = old_path, new = new_path })
  end

  -- Step 3: (★新規) 事前検証を実行
  local is_valid, validation_err = validate_rename_operation(operations)
  if not is_valid then return publish_and_return_error(validation_err) end

  -- Step 4: ユーザーに最終確認
  local prompt_lines = { string.format("Rename '%s' to '%s'?", old_class_name, new_class_name), "" }
  for _, op in ipairs(operations) do table.insert(prompt_lines, op.old .. " -> " .. op.new) end
  
  vim.ui.select({ "Yes, apply rename", "No, cancel" }, { prompt = table.concat(prompt_lines, "\n") }, function(choice)
    if choice ~= "Yes, apply rename" then return log.get().info("Rename canceled by user.") end

    -- Step 5: (★修正) ファイル名変更を先に実行 (ロールバック対応)
    local renamed_files = {} -- 正常にリネームできたファイルを追跡
    local rename_failed = false
    for _, op in ipairs(operations) do
      local ok, rename_err = pcall(vim.loop.fs_rename, op.old, op.new)
      if ok then
        table.insert(renamed_files, { old = op.old, new = op.new })
      else
        log.get().error("File rename failed for %s: %s", op.old, tostring(rename_err))
        rename_failed = true
        break
      end
    end
    -- リネームに失敗した場合、成功したものを元に戻す
    if rename_failed then
      for _, rf in ipairs(renamed_files) do pcall(vim.loop.fs_rename, rf.new, rf.old) end
      return publish_and_return_error("File rename operation failed. Rolling back changes.")
    end

    -- Step 6: (★修正) ファイル内容の置換 (ロールバック対応)
    local content_replace_failed = false 
    -- for _, op in ipairs(operations) do
    --   local ok, replace_err = replace_content_in_file(op.new, old_class_name, new_class_name)
    --   if not ok then
    --     log.get().error("Content replacement failed for %s: %s", op.new, replace_err)
    --     content_replace_failed = true
    --     break
    --   end
    -- end
    -- コンテンツ置換に失敗した場合、ファイル名をすべて元に戻す
    if content_replace_failed then
      for _, op in ipairs(operations) do pcall(vim.loop.fs_rename, op.new, op.old) end
      return publish_and_return_error("Content replacement failed. Rolling back changes.")
    end
    
    -- Step 7: (★修正) 成功イベントの発行
    unl_events.publish(unl_event_types.ON_AFTER_RENAME_CLASS_FILE, {
      status = "success",
      old_class_name = old_class_name,
      new_class_name = new_class_name,
    })
    log.get().info("Rename complete. IMPORTANT: Please regenerate your project files.")
  end)
end

-------------------------------------------------
-- Public API (Dispatcher)
-------------------------------------------------

--- @param opts table: { file_path?, new_class_name? }
function M.run(opts)
  opts = opts or {}

  -- Case 1: 引数が揃っている -> ダイレクト実行
  if opts.file_path and opts.new_class_name then
    log.get().debug("Direct mode: UCM rename")
    execute_file_rename(opts)
    return
  end

  -- Case 2: 引数が足りない -> 対話的UIフローを開始
  log.get().debug("UI mode: UCM rename")
  
  -- UI Flow Step 1: リネーム対象のファイルを選択
  unl_picker.pick({
    kind = "ucm_find_file_for_rename",
    title = "  Select Class File to Rename",
    conf = get_config(),
    exec_cmd = cmd_core.get_fd_files_cmd(),
    cwd = vim.loop.cwd(),
    on_submit = function(selected_file)
      if not selected_file then
        return log.get().info("File selection canceled.")
      end
      
      -- UI Flow Step 2: 新しいクラス名を入力
      local old_name = vim.fn.fnamemodify(selected_file, ":t:r")
      vim.ui.input({ prompt = "Enter New Class Name:", default = old_name }, function(new_name)
        if not new_name or new_name == "" then
          return log.get().info("Rename canceled.")
        end
        
        -- 全ての情報が揃ったので、リネーム処理本体を実行
        execute_file_rename({ file_path = selected_file, new_class_name = new_name })
      end)
    end,
  })
end

return M
