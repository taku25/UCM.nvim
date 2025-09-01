-- lua/UCM/cmd/delete.lua (UIフローとコアロジックを統合)

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
-- Helper Functions
-------------------------------------------------

---
-- (このヘルパー関数は前回の提案のままです)
local function check_permissions(files_to_check)
  for _, path in ipairs(files_to_check) do
    local file, err = io.open(path, "a")
    if not file then
      return false, string.format("Permission denied or file locked: %s (Reason: %s)", path, tostring(err))
    end
    file:close()
  end
  return true, nil
end

-------------------------------------------------
-- Main Execution Flow (Core Logic)
-------------------------------------------------

local function execute_file_deletion(file_path)
  -- (★新規) 失敗イベントの発行とエラーログをまとめたヘルパー関数
  local function publish_and_return_error(message)
    unl_events.publish(unl_event_types.ON_AFTER_DELETE_CLASS_FILE, { status = "failed" })
    log.get().error(message)
    -- 呼び出し元で return するので、この関数は何も返さなくて良い
  end

  -- 1. ヘッダーとソースのペアを解決
  local class_info, err = cmd_core.resolve_class_pair(file_path)
  if not class_info then
    -- (★修正) ヘルパーを呼び出して早期リターン
    return publish_and_return_error(err)
  end

  -- 2. 削除対象のファイルリストを作成
  local files_to_delete = {}
  if class_info.h then table.insert(files_to_delete, class_info.h) end
  if class_info.cpp then table.insert(files_to_delete, class_info.cpp) end

  if #files_to_delete == 0 then
    -- このケースはエラーではないので、イベントは発行せず警告のみ
    return log.get().warn("No existing class files found to delete for: " .. class_info.class_name)
  end

  -- 3. パーミッションを事前チェック
  local can_delete, perm_err = check_permissions(files_to_delete)
  if not can_delete then
    -- (★修正) ヘルパーを呼び出して早期リターン
    return publish_and_return_error(perm_err)
  end

  -- 4. ユーザーに最終確認
  local prompt_str = string.format("Permanently delete class '%s'?\n\n%s", class_info.class_name, table.concat(files_to_delete, "\n"))
  local yes_choice = "Yes, delete files"
  vim.ui.select({ yes_choice, "No, cancel" }, { prompt = prompt_str }, function(choice)
    -- ユーザーによるキャンセルは「失敗」ではないので、イベントは発行しない
    if choice ~= yes_choice then
      return log.get().info("Deletion canceled.")
    end

    -- 5. 実際のファイル削除処理 (この中のロジックは変更なし)
    local all_deleted_successfully = true
    for _, path in ipairs(files_to_delete) do
      local ok, unlink_err = pcall(vim.loop.fs_unlink, path)
      if ok then
        local bufnr = vim.fn.bufnr(path)
        if bufnr > 0 then vim.cmd("bdelete! " .. bufnr) end
      else
        log.get().error("Failed to delete file %s: %s", path, tostring(unlink_err))
        all_deleted_successfully = false
      end
    end

    -- 6. 最終的な結果に基づいてイベントを発行
    local result_payload = {
      status = all_deleted_successfully and "success" or "failed"
    }
    unl_events.publish(unl_event_types.ON_AFTER_DELETE_CLASS_FILE, result_payload)

    if all_deleted_successfully then
      log.get().info("Successfully deleted class '%s'", class_info.class_name)
    else
      log.get().error("Failed to delete one or more files for class '%s'. Please check the log.", class_info.class_name)
    end
  end)
end

-------------------------------------------------
-- Public API (Dispatcher)
-------------------------------------------------

--- @param opts table: { file_path? }
function M.run(opts)
  opts = opts or {}

  -- Case 1: file_pathが引数で渡されている -> ダイレクト実行
  if opts.file_path then
    log.get().debug("Direct mode: UCM delete")
    -- 拡張子がない場合も考慮して、実際のファイルパスを探す
    local actual_filepath
    if vim.fn.filereadable(opts.file_path) == 1 then
      actual_filepath = opts.file_path
    elseif vim.fn.filereadable(opts.file_path .. ".h") == 1 then
      actual_filepath = opts.file_path .. ".h"
    elseif vim.fn.filereadable(opts.file_path .. ".hpp") == 1 then
      actual_filepath = opts.file_path .. ".hpp"
    elseif vim.fn.filereadable(opts.file_path .. ".cpp") == 1 then
      actual_filepath = opts.file_path .. ".cpp"
    elseif vim.fn.filereadable(opts.file_path .. ".inl") == 1 then
      actual_filepath = opts.file_path .. ".inl"
    end
    
    if not actual_filepath then
      return log.get().error("File not found: " .. opts.file_path)
    end
    
    execute_file_deletion(actual_filepath)
    return
  end

  -- Case 2: file_pathがない -> UIでファイルを選択
  log.get().debug("UI mode: UCM delete")

  


  
  -- UNLのPickerを呼び出して、ユーザーにファイルを選択させる
  unl_picker.pick({
    kind = "ucm_find_file_for_delete",
    title = " Select Class File to Delete",
    conf = get_config(),
    logger_name = "UCM",
    exec_cmd = cmd_core.get_fd_files_cmd(),
    on_submit = function(selected)
      if not selected then
        return log.get().info("File selection canceled.")
      end
      execute_file_deletion(selected)
    end,
  })
end

return M
