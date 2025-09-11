-- lua/UCM/cmd/delete.lua

-- (変更) 読み込むモジュールを新しい find_picker に変更
local unl_find_picker = require("UNL.backend.find_picker")
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

local function execute_file_deletion(file_path, opts)
  opts = opts or {}
  local on_complete_callback = opts.on_complete

  local function publish_and_return_error(message)
    local payload = { status = "failed", error = message }
    unl_events.publish(unl_event_types.ON_AFTER_DELETE_CLASS_FILE, payload)
    log.get().error(message)

    if on_complete_callback and type(on_complete_callback) == "function" then
      vim.schedule(function()
        on_complete_callback(false, payload)
      end)
    end
  end

  local class_info, err = cmd_core.resolve_class_pair(file_path)
  if not class_info then
    return publish_and_return_error(err)
  end

  local files_to_delete = {}
  if class_info.h then table.insert(files_to_delete, class_info.h) end
  if class_info.cpp then table.insert(files_to_delete, class_info.cpp) end

  if #files_to_delete == 0 then
    local msg = "No existing class files found to delete for: " .. class_info.class_name
    log.get().warn(msg)
    if on_complete_callback and type(on_complete_callback) == "function" then
      vim.schedule(function()
        on_complete_callback(false, { status = "failed", error = msg })
      end)
    end
    return
  end

  local can_delete, perm_err = check_permissions(files_to_delete)
  if not can_delete then
    return publish_and_return_error(perm_err)
  end

  local prompt_str = string.format("Permanently delete class '%s'?\n\n%s", class_info.class_name, table.concat(files_to_delete, "\n"))
  local yes_choice = "Yes, delete files"
  vim.ui.select({ yes_choice, "No, cancel" }, { prompt = prompt_str }, function(choice)
    if choice ~= yes_choice then
      return log.get().info("Deletion canceled.")
    end

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

    local result_payload = {
      status = all_deleted_successfully and "success" or "failed"
    }
    unl_events.publish(unl_event_types.ON_AFTER_DELETE_CLASS_FILE, result_payload)

    if on_complete_callback and type(on_complete_callback) == "function" then
      vim.schedule(function()
        on_complete_callback(all_deleted_successfully, result_payload)
      end)
    end

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

function M.run(opts)
  opts = opts or {}

  if opts.file_path then
    log.get().debug("Direct mode: UCM delete")
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
      local err_msg = "File not found: " .. opts.file_path
      log.get().error(err_msg)
      if opts.on_complete and type(opts.on_complete) == "function" then
        vim.schedule(function()
          opts.on_complete(false, { status = "failed", error = err_msg })
        end)
      end
      return
    end

    execute_file_deletion(actual_filepath, opts)
    return
  end

  log.get().debug("UI mode: UCM delete")

  -- ▼▼▼ ここからが変更箇所 ▼▼▼
  -- 汎用の unl_picker から、新しい unl_find_picker に呼び出し先を変更
  unl_find_picker.pick({
    title = " Select Class File to Delete",
    conf = get_config(),
    logger_name = "UCM",
    preview_enabled = true, -- <<< この行を追加！ (true/falseを切り替え可能)
    exec_cmd = cmd_core.get_fd_files_cmd(), -- このコマンドが実行される
    on_submit = function(selected)
      if not selected then
        -- ユーザーがピッカーをキャンセルした場合
        log.get().info("File selection canceled.")
        if opts.on_cancel and type(opts.on_cancel) == "function" then
            pcall(opts.on_cancel)
        end
        return
      end
      -- ファイルが選択されたら、後続の処理を実行
      execute_file_deletion(selected, opts)
    end,
  })
  -- ▲▲▲ ここまでが変更箇所 ▲▲▲
end

return M
