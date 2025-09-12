-- lua/UCM/cmd/rename.lua

-- (変更) 読み込むモジュールを新しい find_picker に変更
local unl_find_picker = require("UNL.backend.find_picker")

local unl_finder = require("UNL.finder")
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

local function replace_content_in_file(file_path, old_name, new_name)
  local read_ok, lines = pcall(vim.fn.readfile, file_path)
  if not read_ok then return false, "Failed to read file: " .. tostring(lines) end
  local content = table.concat(lines, "\n")
  content = content:gsub("\b" .. old_name .. "\b", new_name)
  content = content:gsub('"' .. old_name .. '%.generated%.h"', '"' .. new_name .. '.generated.h"')
  local write_ok, write_err = pcall(vim.fn.writefile, vim.split(content, '\n'), file_path)
  if not write_ok then return false, "Failed to write updated content: " .. tostring(write_err) end
  return true
end

local function validate_rename_operation(operations)
  for _, op in ipairs(operations) do
    local src_file, src_err = io.open(op.old, "a")
    if not src_file then
      return false, string.format("Permission denied on source file: %s (Reason: %s)", op.old, tostring(src_err))
    end
    src_file:close()
    if vim.fn.filereadable(op.new) == 1 or vim.fn.isdirectory(op.new) == 1 then
      return false, string.format("Destination file already exists, rename aborted to prevent overwrite: %s", op.new)
    end
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

local function execute_file_rename(opts)
  local on_complete_callback = opts.on_complete

  local function publish_and_return_error(message)
    local payload = { status = "failed", error = message }
    unl_events.publish(unl_event_types.ON_AFTER_RENAME_CLASS_FILE, payload)
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

  local old_class_name = class_info.class_name
  local new_class_name = opts.new_class_name
  if old_class_name == new_class_name then return log.get().info("Rename canceled: names are identical.") end

  local operations = {}
  local files_to_process = {}
  if class_info.h then table.insert(files_to_process, class_info.h) end
  if class_info.cpp then table.insert(files_to_process, class_info.cpp) end
  if #files_to_process == 0 then return publish_and_return_error("No existing class files found to rename.") end

  for _, old_path in ipairs(files_to_process) do
    local new_path = fs.joinpath(fs.dirname(old_path), new_class_name .. "." .. vim.fn.fnamemodify(old_path, ":e"))
    table.insert(operations, { old = old_path, new = new_path })
  end

  local is_valid, validation_err = validate_rename_operation(operations)
  if not is_valid then return publish_and_return_error(validation_err) end

  local prompt_lines = { string.format("Rename '%s' to '%s'?", old_class_name, new_class_name), "" }
  for _, op in ipairs(operations) do table.insert(prompt_lines, op.old .. " -> " .. op.new) end
  
  vim.ui.select({ "Yes, apply rename", "No, cancel" }, { prompt = table.concat(prompt_lines, "\n") }, function(choice)
    if choice ~= "Yes, apply rename" then return log.get().info("Rename canceled by user.") end

    local renamed_files = {}
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
    if rename_failed then
      for _, rf in ipairs(renamed_files) do pcall(vim.loop.fs_rename, rf.new, rf.old) end
      return publish_and_return_error("File rename operation failed. Rolling back changes.")
    end

    local content_replace_failed = false
    if content_replace_failed then
      for _, op in ipairs(operations) do pcall(vim.loop.fs_rename, op.new, op.old) end
      return publish_and_return_error("Content replacement failed. Rolling back changes.")
    end
    
    local success_payload = {
      status = "success",
      old_class_name = old_class_name,
      new_class_name = new_class_name,
      module = module,
    }
    unl_events.publish(unl_event_types.ON_AFTER_RENAME_CLASS_FILE, success_payload)

    if on_complete_callback and type(on_complete_callback) == "function" then
      vim.schedule(function()
        on_complete_callback(true, success_payload)
      end)
    end
    log.get().info("Rename complete. IMPORTANT: Please regenerate your project files.")
  end)
end

-------------------------------------------------
-- Public API (Dispatcher)
-------------------------------------------------

local function ask_for_new_name_and_execute(file_path, original_opts)
  local old_name = vim.fn.fnamemodify(file_path, ":t:r")
  
  vim.ui.input({ prompt = "Enter New Class Name:", default = old_name }, function(new_name)
    if not new_name or new_name == "" or new_name == old_name then
      log.get().info("Rename canceled.")
      -- ユーザーがキャンセルした場合、on_cancelコールバックを呼ぶのが親切
      if original_opts.on_cancel and type(original_opts.on_cancel) == "function" then
        pcall(original_opts.on_cancel)
      end
      return
    end
    
    -- 元のオプションと新しい情報をマージして、コアロジックに渡す
    local final_opts = vim.deepcopy(original_opts)
    final_opts.file_path = file_path
    final_opts.new_class_name = new_name
    
    execute_file_rename(final_opts)
  end)
end


---
-- Public API (Dispatcher) - 3つのシナリオを捌くように修正
function M.run(opts)
  opts = opts or {}
  log.get().debug("UCM rename called with opts: %s", vim.inspect(opts))

  -- シナリオ3: 非UIモード (API/テスト用)
  if opts.file_path and opts.new_class_name then
    log.get().debug("Direct mode: UCM rename")
    execute_file_rename(opts)
    return
  end

  -- シナリオ2: 半UIモード (neo-treeからの呼び出し)
  if opts.file_path then
    log.get().debug("Semi-interactive mode: file_path provided, asking for new name.")
    ask_for_new_name_and_execute(opts.file_path, opts)
    return
  end

  -- シナリオ1: 完全UIモード (ユーザーが:UCM renameを実行)
  log.get().debug("UI mode: UCM rename")
  
  unl_find_picker.pick({
    title = "  Select Class File to Rename",
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
      ask_for_new_name_and_execute(selected_file, opts)
    end,
  })
end

return M
