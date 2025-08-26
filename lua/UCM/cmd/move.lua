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

-- 全ての情報が揃った後に呼ばれる、移動処理の本体
local function execute_file_move(opts) -- opts = { file_path, target_dir }
  -- 1. 移動元のクラスペアを解決
  local class_info, err = cmd_core.resolve_class_pair(opts.file_path)
  if not class_info then return log.get().error(err) end

  -- 2. 移動先のディレクトリが有効なモジュール内か検証
  local dest_context, dest_err = cmd_core.resolve_creation_context(opts.target_dir)
  if not dest_context then
    return log.get().error("Invalid destination: " .. (dest_err or "Not within a valid module."))
  end

  local files_to_move = {}
  if class_info.h then table.insert(files_to_move, class_info.h) end
  if class_info.cpp then table.insert(files_to_move, class_info.cpp) end

  if #files_to_move == 0 then return log.get().error("No existing files found to move.") end
  
  -- 3. 移動前と移動後のパスを計算し、ユーザーに最終確認
  local prompt_lines = { string.format("Move class '%s'?", class_info.class_name), "" }
  local operations = {}
  for _, old_path in ipairs(files_to_move) do
    local filename = vim.fn.fnamemodify(old_path, ":t")
    -- resolve_creation_contextから正しいヘッダー/ソースディレクトリを取得
    local new_dir = old_path:match("%.h$") and dest_context.header_dir or dest_context.source_dir
    local new_path = fs.joinpath(new_dir, filename)
    table.insert(prompt_lines, old_path .. " -> " .. new_path)
    table.insert(operations, { old = old_path, new = new_path })
  end

  vim.ui.select({ "Yes, move files", "No, cancel" }, { prompt = table.concat(prompt_lines, "\n") }, function(choice)
    if choice ~= "Yes, move files" then return log.get().info("Move canceled.") end

    -- 4. ファイル移動処理
    for _, op in ipairs(operations) do
      local rename_ok, rename_err = pcall(vim.loop.fs_rename, op.old, op.new)
      if not rename_ok then
        return log.get().error("File move failed: " .. tostring(rename_err))
      end
    end

    log.get().info("Move complete. IMPORTANT: You may need to update #include paths and regenerate project files.")
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
      title = "Select Destination Directory for '" .. vim.fn.fnamemodify(source_file, ":t:r") .. "'",
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
