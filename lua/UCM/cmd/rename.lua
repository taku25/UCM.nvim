-- lua/UCM/cmd/rename.lua

local cmd_core = require("UCM.cmd.core")
local logger = require("UCM.logger")
local fs = require("vim.fs")

-- (ヘルパー関数は変更なし)
local function find_actual_filepath(user_path)
  if vim.fn.filereadable(user_path) == 1 then return user_path end
  local path_h = user_path .. ".h"; if vim.fn.filereadable(path_h) == 1 then return path_h end
  local path_cpp = user_path .. ".cpp"; if vim.fn.filereadable(path_cpp) == 1 then return path_cpp end
  return nil
end

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

local function on_complete(result, opts)
        
  logger.info(string.format("Renamed '%s' to '%s'", result.old_class_name, result.new_class_name))

  --ユーザーのコンプリートも呼ぶ
  if opts.on_comple then
     opts.on_comple(result)
  end
end

local function on_cancel(result, opts)
  --ユーザーのキャンセルも呼ぶ
  logger.error("Operation failed: " .. tostring(result))
  if opts.on_cancel then
     opts.on_cancel(result)
  end
end

local function on_exit(result, opts)
  --ユーザーのキャンセルも呼ぶ
  logger.error("Operation failed: " .. tostring(result))
  if opts.on_exit then
     opts.on_exit(result)
  end
end

local M = {}

---
-- @param opts table
-- @param on_complete function: A callback function(ok, result) to be called on completion.
function M.run(opts)
  local actual_filepath = find_actual_filepath(opts.file_path)
  if not actual_filepath then
    return on_exit("File not found: " .. opts.file_path, opts)
  end

  local class_info, err = cmd_core.resolve_class_pair(actual_filepath)
  if not class_info then
    return on_exit(err, opts)
  end

  class_info.old_class_name = class_info.class_name
  class_info.new_class_name = opts.new_class_name

  if class_info.old_class_name == class_info.new_class_name then
    return on_exit("canceled", opts) -- Cancel quietly if names are the same
  end

  local files_to_process = {}
  if class_info.h then table.insert(files_to_process, class_info.h) end
  if class_info.cpp then table.insert(files_to_process, class_info.cpp) end

  if #files_to_process == 0 then
    return on_exit(false, "No existing files found to rename.", opts)
  end

  -- Step A: Build the detailed prompt message for the UI
  local prompt_lines = {}
  for _, old_path in ipairs(files_to_process) do
    local dir = fs.dirname(old_path)
    local ext = vim.fn.fnamemodify(old_path, ":e")
    local new_path = fs.joinpath(dir, class_info.new_class_name .. "." .. ext)
    table.insert(prompt_lines, old_path)
    table.insert(prompt_lines, "  ↓")
    table.insert(prompt_lines, new_path)
    table.insert(prompt_lines, "---")
  end
  table.remove(prompt_lines) -- Remove the last "---"
  local detailed_changes_str = table.concat(prompt_lines, "\n")
  local prompt_str = string.format("Rename '%s' to '%s'?\n\n%s", class_info.old_class_name, class_info.new_class_name, detailed_changes_str)

  -- Step B: Show the UI to the user and handle the result in a callback
  vim.ui.select(
    { "Yes, apply rename", "No, cancel" },
    { prompt = prompt_str, format_item = function(item) return "  " .. item end },
    function(choice)
      if not choice or choice ~= "Yes, apply rename" then
        return on_cancel("canceled", opts)
      end

      -- User confirmed, now execute the rename logic
      for _, path in ipairs(files_to_process) do
        local ok, replace_err = replace_content_in_file(path, class_info.old_class_name, class_info.new_class_name)
        if not ok then
          return on_exit("Content replacement failed: " .. replace_err, opts)
        end
      end

      logger.info("--- Renaming files ---")
      for _, old_path in ipairs(files_to_process) do
        local dir = fs.dirname(old_path)
        local ext = vim.fn.fnamemodify(old_path, ":e")
        local new_path = fs.joinpath(dir, class_info.new_class_name .. "." .. ext)
        local rename_ok, rename_err = pcall(os.rename, old_path, new_path)
        if rename_ok then
          logger.info(old_path .. "\n  ↓\n" .. new_path .. "\n---")
        else
          return on_exit("File rename operation failed: " .. tostring(rename_err), opts)
        end
      end

      logger.info("Rename complete. IMPORTANT: Please regenerate your project files.")
      on_complete(class_info, opts) -- Success!
    end
  )
end

return M
