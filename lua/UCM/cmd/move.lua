-- lua/UCM/cmd/move.lu-- lua/UCM/cmd/move.lua

-- (変更) 読み込むモジュールを新しい find_picker に変更
local unl_picker = require("UNL.picker")
local cmd_core = require("UCM.cmd.core")
local log = require("UCM.logger")
local fs = require("vim.fs")
local unl_events = require("UNL.event.events")
local unl_event_types = require("UNL.event.types")
local unl_finder = require("UNL.finder")

local function get_config()
  return require("UNL.config").get("UCM")
end

local M = {}

-------------------------------------------------
-- Helper Functions
-------------------------------------------------

local function validate_move_operation(operations)
  for _, op in ipairs(operations) do
    local src_file, src_err = io.open(op.old, "a")
    if not src_file then
      return false, string.format("Permission denied on source file: %s (Reason: %s)", op.old, tostring(src_err))
    end
    src_file:close()
    if vim.fn.filereadable(op.new) == 1 or vim.fn.isdirectory(op.new) == 1 then
      return false, string.format("Destination file already exists, move aborted to prevent overwrite: %s", op.new)
    end
    local dest_dir = fs.dirname(op.new)
    local test_file_path = fs.joinpath(dest_dir, ".ucm_write_test")
    local dest_dir_file, dest_dir_err = io.open(test_file_path, "w")
    if not dest_dir_file then
      return false, string.format("Permission denied in destination directory: %s (Reason: %s)", dest_dir, tostring(dest_dir_err))
    end
    dest_dir_file:close()
    pcall(vim.loop.fs_unlink, test_file_path)
  end
  return true, nil
end

---
-- 移動された .cpp の中身を読み取り、.h への #include を修正する
-- @param operations table ( {old="...", new="..."} のリスト)
-- @param class_info table (cmd_core.resolve_class_pair の戻り値)
-- @return boolean, string|nil 成功/失敗、エラーメッセージ
local function replace_includes_for_move(operations, class_info)
  local log_instance = log.get()
  local new_header_path, new_source_path, old_header_path = nil, nil, nil
  
  for _, op in ipairs(operations) do
    if op.new:match("%.h$") then new_header_path = op.new end
    if op.new:match("%.cpp$") then new_source_path = op.new end
  end
  
  old_header_path = class_info.h -- 元のヘッダーパス

  -- .cpp と .h の両方が移動対象だった場合のみ実行
  if not (new_source_path and new_header_path and old_header_path) then
    log_instance.debug("Header or source file missing from move op, skipping include fix.")
    return true -- エラーではない
  end

  -- 1. 古いインクルードパスを計算
  local old_relative_include = cmd_core.get_relative_include_path(old_header_path)
  if not old_relative_include then
    log_instance.warn("Could not determine OLD relative include path for %s. Skipping .cpp update.", old_header_path)
    return true -- エラーではない
  end
  
  -- 2. 新しいインクルードパスを計算
  local new_relative_include = cmd_core.get_relative_include_path(new_header_path)
  if not new_relative_include then
    log_instance.warn("Could not determine NEW relative include path for %s. Skipping .cpp update.", new_header_path)
    return true -- エラーではない
  end

  if old_relative_include == new_relative_include then
    log_instance.debug("Include paths are identical, no replacement needed.")
    return true
  end

  -- 3. .cpp ファイルの中身を置換
  local read_ok, s_lines = pcall(vim.fn.readfile, new_source_path)
  if not read_ok then return false, "Failed to read new source file: " .. new_source_path end
  
  local content = table.concat(s_lines, "\n")
  
  -- [!] 古いインクルードパスをピンポイントで置換
  local old_include_line = '#include "' .. old_relative_include .. '"'
  local new_include_line = '#include "' .. new_relative_include .. '"'
  
  local new_content, count = content:gsub(old_include_line, new_include_line, 1) -- 1回だけ置換
  
  if count > 0 then
    log_instance.debug("Fixing .h include in: %s", new_source_path)
    local write_ok, write_err = pcall(vim.fn.writefile, vim.split(new_content, '\n'), new_source_path)
    if not write_ok then return false, "Failed to write updated source content: " .. tostring(write_err) end
  else
    log_instance.warn("Could not find old include line (%s) in %s. File may need manual update.", old_include_line, new_source_path)
  end
  
  return true, nil
end

-------------------------------------------------
-- Main Execution Flow (Core Logic)
-------------------------------------------------
local function execute_file_move(opts)
  local on_complete_callback = opts.on_complete

  local function publish_and_return_error(message)
    local payload = { status = "failed", error = message }
    unl_events.publish(unl_event_types.ON_AFTER_MOVE_CLASS_FILE, payload)
    log.get().error(message)
    if on_complete_callback and type(on_complete_callback) == "function" then
      vim.schedule(function()
        on_complete_callback(false, payload)
      end)
    end
  end

  local module = unl_finder.module.find_module(opts.file_path)
  local class_info, err = cmd_core.resolve_class_pair(opts.file_path)
  if not class_info then return publish_and_return_error(err) end

  local dest_context, dest_err = cmd_core.resolve_creation_context(opts.target_dir)
  if not dest_context then
    return publish_and_return_error("Invalid destination: " .. (dest_err or "Not within a valid module."))
  end

  local files_to_move = {}
  if class_info.h then table.insert(files_to_move, class_info.h) end
  if class_info.cpp then table.insert(files_to_move, class_info.cpp) end
  if #files_to_move == 0 then
    return publish_and_return_error("No existing files found to move for class: " .. class_info.class_name)
  end

  local operations = {}
  for _, old_path in ipairs(files_to_move) do
    local filename = vim.fn.fnamemodify(old_path, ":t")
    local new_dir = old_path:match("%.h$") and dest_context.header_dir or dest_context.source_dir
    local new_path = fs.joinpath(new_dir, filename)
    table.insert(operations, { old = old_path, new = new_path })
  end

  local is_valid, validation_err = validate_move_operation(operations)
  if not is_valid then
    return publish_and_return_error(validation_err)
  end

  local prompt_lines = { string.format("Move class '%s'?", class_info.class_name), "" }
  for _, op in ipairs(operations) do
    table.insert(prompt_lines, op.old .. " -> " .. op.new)
  end

  -- ▼▼▼ 変更箇所 ▼▼▼
  local prompt_str = table.concat(prompt_lines, "\n")
  local choices = "&Yes, move files\n&No, cancel"
  local decision = vim.fn.confirm(prompt_str, choices)

  if decision ~= 1 then
    return log.get().info("Move canceled.")
  end
  -- ▲▲▲ 変更ここまで ▲▲▲

  local all_moved_successfully = true
  for _, op in ipairs(operations) do
    local rename_ok, rename_err = pcall(vim.loop.fs_rename, op.old, op.new)
    if not rename_ok then
      log.get().error("File move failed for %s: %s", op.old, tostring(rename_err))
      all_moved_successfully = false
      break
    end
  end


  if all_moved_successfully then
    -- ファイル移動成功！ 次に #include を修正する
    log.get().debug("Files moved. Now attempting to fix #includes...")
    local fix_ok, fix_err = replace_includes_for_move(operations, class_info)
    
    if not fix_ok then
      -- #include の修正に失敗した場合
      log.get().error("Failed to fix #includes: %s. Rolling back file move.", tostring(fix_err))
      -- ロールバック
      for _, op in ipairs(operations) do pcall(vim.loop.fs_rename, op.new, op.old) end
      return publish_and_return_error("Content replacement failed. Rolling back changes.")
    end
  else
    -- ファイル移動自体に失敗した場合
    log.get().error("An error occurred during the move operation. Some files may not have been moved.")
    -- ロールバック (rename_failed のロジックと重複するが、念のため)
    for _, op in ipairs(operations) do if vim.fn.filereadable(op.new) == 1 then pcall(vim.loop.fs_rename, op.new, op.old) end end
    return publish_and_return_error("File move operation failed. Rolling back changes.")
  end

  local result_payload = {
    status = all_moved_successfully and "success" or "failed",
    operations = operations,
    module = module,
  }
  unl_events.publish(unl_event_types.ON_AFTER_MOVE_CLASS_FILE, result_payload)

  if on_complete_callback and type(on_complete_callback) == "function" then
    vim.schedule(function()
      on_complete_callback(all_moved_successfully, result_payload)
    end)
  end

  if all_moved_successfully then
    log.get().info("Move complete. IMPORTANT: You may need to update #include paths and regenerate project files.")
  else
    log.get().error("An error occurred during the move operation. Some files may not have been moved.")
  end
end

-------------------------------------------------
-- Public API (Dispatcher)
-------------------------------------------------

local function ask_for_destination_and_execute(source_file, original_opts)
  -- ★★★ ここからが修正箇所 ★★★
  -- 1. 移動元のファイルパスから、プロジェクトではなく「モジュール」のルートを特定する
  local unl_finder = require("UNL.finder")
  local module_root = unl_finder.module.find_module_root(source_file)
  -- ★★★ 修正箇所ここまで ★★★
  --
  -- find_picker を使って移動先のディレクトリを選択させる
  unl_picker.open({
    title = "  Select Destination for '" .. vim.fn.fnamemodify(source_file, ":t:r") .. "'",
    conf = get_config(),
    logger_name = "UCM",
    exec_cmd = cmd_core.get_fd_directory_cmd(module_root),
    preview_enabled = false,
    on_submit = function(selected_dir)
      if not selected_dir then
        log.get().info("Destination selection canceled.")
        if original_opts.on_cancel then pcall(original_opts.on_cancel) end
        return
      end
      
      -- 元のオプションと新しい情報をマージして、コアロジックに渡す
      local final_opts = vim.deepcopy(original_opts)
      final_opts.file_path = source_file
      final_opts.target_dir = selected_dir
      
      execute_file_move(final_opts)
    end,
  })
end


---
-- Public API (Dispatcher) - 3つのシナリオを捌くように修正
function M.run(opts)
  opts = opts or {}
  log.get().debug("UCM move called with opts: %s", vim.inspect(opts))

  -- シナリオ3: 非UIモード (API/テスト用)
  if opts.file_path and opts.target_dir then
    log.get().debug("Direct mode: UCM move")
    execute_file_move(opts)
    return
  end

  -- シナリオ2: 半UIモード (neo-treeからの呼び出し)
  if opts.file_path then
    log.get().debug("Semi-interactive mode: file_path provided, asking for destination.")
    ask_for_destination_and_execute(opts.file_path, opts)
    return
  end

  -- シナリオ1: 完全UIモード (ユーザーが:UCM moveを実行)
  log.get().debug("UI mode: UCM move")
  
  -- find_picker を使って移動元のファイルを選択させる
  unl_picker.open({
    title = " Select Class File to Move",
    conf = get_config(),
    logger_name = "UCM",
    exec_cmd = cmd_core.get_fd_files_cmd(),
    preview_enabled = true,
    on_submit = function(selected_file)
      if not selected_file then
        log.get().info("File selection canceled.")
        if opts.on_cancel then pcall(opts.on_cancel) end
        return
      end
      
      -- ファイルが選択されたら、ヘルパー関数を呼び出して次のステップへ
      ask_for_destination_and_execute(selected_file, opts)
    end,
  })
end

return M


