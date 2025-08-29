-- lua/UCM/cmd/move.lua (UIフローとコアロジックを統合)

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

---
-- 移動操作が可能か（権限、上書き防止など）を事前に検証する
-- @param operations table: { { old = "old_path", new = "new_path" }, ... }
-- @return boolean, string|nil
local function validate_move_operation(operations)
  for _, op in ipairs(operations) do
    -- 1. 移動元ファイルの権限チェック
    local src_file, src_err = io.open(op.old, "a")
    if not src_file then
      return false, string.format("Permission denied on source file: %s (Reason: %s)", op.old, tostring(src_err))
    end
    src_file:close()

    -- 2. 移動先ファイルが既に存在しないかチェック (上書き防止)
    if vim.fn.filereadable(op.new) == 1 or vim.fn.isdirectory(op.new) == 1 then
      return false, string.format("Destination file already exists, move aborted to prevent overwrite: %s", op.new)
    end
    
    -- 3. 移動先ディレクトリの書き込み権限チェック
    local dest_dir = fs.dirname(op.new)
    local test_file_path = fs.joinpath(dest_dir, ".ucm_write_test")
    local dest_dir_file, dest_dir_err = io.open(test_file_path, "w")
    if not dest_dir_file then
      return false, string.format("Permission denied in destination directory: %s (Reason: %s)", dest_dir, tostring(dest_dir_err))
    end
    dest_dir_file:close()
    pcall(vim.loop.fs_unlink, test_file_path) -- テストファイルを削除
  end
  return true, nil
end

-------------------------------------------------
-- Main Execution Flow (Core Logic)
-------------------------------------------------

local function execute_file_move(opts) -- opts = { file_path, target_dir }
  -- (★新規) 失敗イベントの発行とエラーログをまとめたヘルパー関数
  local function publish_and_return_error(message)
    unl_events.publish(unl_types.ON_AFTER_MOVE_CLASS_FILE, { status = "failed" })
    log.get().error(message)
  end

  -- 1. 移動元のクラスペアを解決
  local class_info, err = cmd_core.resolve_class_pair(opts.file_path)
  if not class_info then return publish_and_return_error(err) end

  -- 2. 移動先のディレクトリが有効か検証
  local dest_context, dest_err = cmd_core.resolve_creation_context(opts.target_dir)
  if not dest_context then
    return publish_and_return_error("Invalid destination: " .. (dest_err or "Not within a valid module."))
  end

  local files_to_move = {}
  if class_info.h then table.insert(files_to_move, class_info.h) end
  if class_info.cpp then table.insert(files_to_move, class_info.cpp) end

  if #files_to_move == 0 then
    -- 移動対象がないのはエラーとして扱う
    return publish_and_return_error("No existing files found to move for class: " .. class_info.class_name)
  end
  
  -- 3. 移動オペレーションのリストを作成
  local operations = {}
  for _, old_path in ipairs(files_to_move) do
    local filename = vim.fn.fnamemodify(old_path, ":t")
    local new_dir = old_path:match("%.h$") and dest_context.header_dir or dest_context.source_dir
    local new_path = fs.joinpath(new_dir, filename)
    table.insert(operations, { old = old_path, new = new_path })
  end

  -- 4. (★新規) 移動操作を事前に検証
  local is_valid, validation_err = validate_move_operation(operations)
  if not is_valid then
    return publish_and_return_error(validation_err)
  end

  -- 5. ユーザーに最終確認
  local prompt_lines = { string.format("Move class '%s'?", class_info.class_name), "" }
  for _, op in ipairs(operations) do
    table.insert(prompt_lines, op.old .. " -> " .. op.new)
  end
  
  vim.ui.select({ "Yes, move files", "No, cancel" }, { prompt = table.concat(prompt_lines, "\n") }, function(choice)
    if choice ~= "Yes, move files" then return log.get().info("Move canceled.") end

    -- 6. ファイル移動処理
    local all_moved_successfully = true
    for _, op in ipairs(operations) do
      local rename_ok, rename_err = pcall(vim.loop.fs_rename, op.old, op.new)
      if not rename_ok then
        log.get().error("File move failed for %s: %s", op.old, tostring(rename_err))
        all_moved_successfully = false
        break -- 1つでも失敗したらループを抜ける
      end
    end

    -- 7. (★修正) 最終的な結果に基づいてイベントを発行
    local result_payload = { status = all_moved_successfully and "success" or "failed" }
    unl_events.publish(unl_types.ON_AFTER_MOVE_CLASS_FILE, result_payload)

    if all_moved_successfully then
      log.get().info("Move complete. IMPORTANT: You may need to update #include paths and regenerate project files.")
    else
      log.get().error("An error occurred during the move operation. Some files may not have been moved.")
    end
  end)
end

-------------------------------------------------
-- Public API (Dispatcher)
-------------------------------------------------

--- @param opts table: { file_path?, target_dir? }
function M.run(opts)
  opts = opts or {}

  -- Case 1: 引数が揃っている -> ダイレクト実行
  if opts.file_path and opts.target_dir then
    return execute_file_move(opts)
  end

  -- Case 2: 引数が足りない -> 対話的UIフローを開始
  local collected_opts = {}

  -- UI Flow Step 2: 移動先のディレクトリを選択
  local function ask_for_destination(source_file)
    collected_opts.file_path = source_file
    
    unl_picker.pick({
      kind = "ucm_select_dir_for_move",
      title = "  Select Destination Directory for '" .. vim.fn.fnamemodify(source_file, ":t:r") .. "'",
      conf = get_config(),
      -- プロジェクト内の Source/Plugins ディレクトリを検索
      exec_cmd = cmd_core.get_fd_directory_cmd(),
      cwd = vim.loop.cwd(),
      on_submit = function(selected_dir)
        if not selected_dir then return log.get().info("Directory selection canceled.") end
        collected_opts.target_dir = selected_dir
        execute_file_move(collected_opts)
      end,
    })
  end
  -- UI Flow Step 1: 移動対象のファイルを選択
  unl_picker.pick({
    kind = "ucm_find_file_for_move",
    title = "Select Class File to Move",
    conf = get_config(),
    exec_cmd = cmd_core.get_fd_files_cmd(),
    cwd = vim.loop.cwd(),
    on_submit = function(selected_file)
      if not selected_file then return log.get().info("File selection canceled.") end
      ask_for_destination(selected_file) -- 次のステップへ
    end,
  })
end

return M
