-- lua/UCM/cmd/switch.lua

local cmd_core = require("UCM.cmd.core")
local log = require("UCM.logger") -- 変数名を log に変更して統一

local M = {}

function M.run(opts)
  opts = opts or {} 
  opts.current_file_path = opts.current_file_path or vim.api.nvim_buf_get_name(0)

  -- Step 1: Resolve the class file pair from the current buffer path
  local class_info, err = cmd_core.resolve_class_pair(opts.current_file_path)
  if not class_info then
    -- クラスペア解決自体の失敗（.build.csが見つからないなど）
    log.get().warn(err) -- ★修正: log.get() を経由する
    return false, err
  end

  -- Step 2: Determine the path of the alternate file
  -- ヘッダーならCpp、Cppならヘッダーをターゲットにする
  local alternate_path = class_info.is_header_input and class_info.cpp or class_info.h

  -- Step 3: Switch to the file if it exists
  if alternate_path then
    vim.cmd("edit " .. vim.fn.fnameescape(alternate_path))
    return true
  else
    -- ペアは見つかったが、対になるファイルが存在しない場合
    local err_msg = "Alternate file does not exist for: " .. class_info.class_name
    log.get().warn(err_msg) -- ★修正: log.get() を経由する
    return false, err_msg
  end
end

return M
