-- lua/UCM/cmd/delete.lua

local cmd_core = require("UCM.cmd.core")
local logger = require("UCM.logger")

local function find_actual_filepath(user_path)
  if vim.fn.filereadable(user_path) == 1 then return user_path end
  local path_h = user_path .. ".h"; if vim.fn.filereadable(path_h) == 1 then return path_h end
  local path_cpp = user_path .. ".cpp"; if vim.fn.filereadable(path_cpp) == 1 then return path_cpp end
  return nil
end

local M = {}

local function on_complete(result, opts)
        
  logger.info("Successfully deleted class files for: " .. result.class_name)

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

-- @param opts table
-- @param on_complete function: A callback function(ok, result) to be called on completion.
function M.run(opts)
  local actual_filepath = find_actual_filepath(opts.file_path)
  if not actual_filepath then
    -- 失敗したら即座にコールバックを呼んで終了
    return on_exit("File not found: " .. opts.file_path, opts)
  end

  local class_info, err = cmd_core.resolve_class_pair(actual_filepath)
  if not class_info then
    return on_exit(err, opts)
  end

  local files_to_delete = {}
  if class_info.h then table.insert(files_to_delete, class_info.h) end
  if class_info.cpp then table.insert(files_to_delete, class_info.cpp) end

  if #files_to_delete == 0 then
    return on_exit("No existing files found to delete.", opts)
  end

  local prompt_str = string.format("Delete class '%s'?\n\n%s", class_info.class_name, table.concat(files_to_delete, "\n"))

  vim.ui.select(
    { "Yes, permanently delete", "No, cancel" },
    { prompt = prompt_str, format_item = function(item) return "  " .. item end },
    function(choice)
      if not choice or choice ~= "Yes, permanently delete" then
        -- ユーザーがキャンセルした場合
        return on_cancel("canceled", opts)
      end

      -- ユーザーが"Yes"を選んだ場合
      for _, file_path in ipairs(files_to_delete) do
        pcall(os.remove, file_path)
        -- (バッファを閉じる処理は省略)
      end
      
      -- 成功した場合
      on_complete(class_info, opts)
    end
  )
end

return M
