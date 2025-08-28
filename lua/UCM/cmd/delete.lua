-- lua/UCM/cmd/delete.lua (UIフローとコアロジックを統合)

local unl_picker = require("UNL.backend.picker")
local cmd_core = require("UCM.cmd.core")
local log = require("UCM.logger")
local fs = require("vim.fs")


local function get_config()
  return require("UNL.config").get("UCM")
end

local M = {}

-------------------------------------------------
-- Main Execution Flow (Core Logic)
-------------------------------------------------

-- ファイルパスが確定した後に呼ばれる、ファイル削除の本体
local function execute_file_deletion(file_path)
  -- 1. ヘッダーとソースのペアを解決
  local class_info, err = cmd_core.resolve_class_pair(file_path)
  if not class_info then
    return log.get().error(err)
  end

  -- 2. 削除対象のファイルリストを作成
  local files_to_delete = {}
  if class_info.h then table.insert(files_to_delete, class_info.h) end
  if class_info.cpp then table.insert(files_to_delete, class_info.cpp) end

  if #files_to_delete == 0 then
    return log.get().warn("No existing class files found to delete for: " .. class_info.class_name)
  end

  -- 3. ユーザーに最終確認
  local prompt_str = string.format("Permanently delete class '%s'?\n\n%s", class_info.class_name, table.concat(files_to_delete, "\n"))
  local yes_choice = "Yes, delete files"
  vim.ui.select({ yes_choice, "No, cancel" }, { prompt = prompt_str }, function(choice)
    if choice ~= yes_choice then
      return log.get().info("Deletion canceled.")
    end

    -- 4. 実際のファイル削除処理
    local deleted_files = {}
    for _, path in ipairs(files_to_delete) do
      local ok, unlink_err = pcall(vim.loop.fs_unlink, path)
      if ok then
        table.insert(deleted_files, path)
        -- 開いているバッファを削除
        local bufnr = vim.fn.bufnr(path)
        if bufnr > 0 then
          vim.cmd("bdelete! " .. bufnr)
        end
      else
        log.get().error("Failed to delete file %s: %s", path, tostring(unlink_err))
      end
    end

    if #deleted_files > 0 then
      log.get().info("Successfully deleted class '%s'", class_info.class_name)
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
