-- lua/UCM/cmd/rename.lua (UIフローとコアロジックを統合)

local unl_picker = require("UNL.backend.picker")
local cmd_core = require("UCM.cmd.core")
local log = require("UCM.logger")
local fs = require("vim.fs")

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

-------------------------------------------------
-- Main Execution Flow (Core Logic)
-------------------------------------------------

-- 全ての情報が揃った後に呼ばれる、リネーム処理の本体
local function execute_file_rename(opts) -- opts = { file_path, new_class_name }
  -- 1. クラスのペア (.h と .cpp) を解決
  local class_info, err = cmd_core.resolve_class_pair(opts.file_path)
  if not class_info then
    return log.get().error(err)
  end

  local old_class_name = class_info.class_name
  local new_class_name = opts.new_class_name

  if old_class_name == new_class_name then
    return log.get().info("Rename canceled: names are identical.")
  end

  local files_to_process = {}
  if class_info.h then table.insert(files_to_process, class_info.h) end
  if class_info.cpp then table.insert(files_to_process, class_info.cpp) end

  if #files_to_process == 0 then
    return log.get().error("No existing class files found to rename.")
  end

  -- 2. ユーザーに最終確認
  local prompt_lines = { string.format("Rename '%s' to '%s'?", old_class_name, new_class_name), "" }
  for _, old_path in ipairs(files_to_process) do
    local new_path = fs.joinpath(fs.dirname(old_path), new_class_name .. "." .. vim.fn.fnamemodify(old_path, ":e"))
    table.insert(prompt_lines, old_path .. " -> " .. new_path)
  end
  
  vim.ui.select({ "Yes, apply rename", "No, cancel" }, { prompt = table.concat(prompt_lines, "\n") }, function(choice)
    if choice ~= "Yes, apply rename" then
      return log.get().info("Rename canceled by user.")
    end

    -- 3. ファイル内容の置換
    for _, path in ipairs(files_to_process) do
      local ok, replace_err = replace_content_in_file(path, old_class_name, new_class_name)
      if not ok then
        return log.get().error("Content replacement failed: " .. replace_err)
      end
    end

    -- 4. ファイル自体のリネーム
    for _, old_path in ipairs(files_to_process) do
      local new_path = fs.joinpath(fs.dirname(old_path), new_class_name .. "." .. vim.fn.fnamemodify(old_path, ":e"))
      local rename_ok, rename_err = pcall(vim.loop.fs_rename, old_path, new_path)
      if not rename_ok then
        -- (ここでロールバック処理を入れることも可能だが、今回はエラー表示のみ)
        return log.get().error("File rename operation failed: " .. tostring(rename_err))
      end
    end

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
