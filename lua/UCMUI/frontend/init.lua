-- lua/UCMUI/frontend/init.lua

local conf = require("UCM.conf")
local logger = require("UCM.logger")

local M = {}

local function get_backend()
  local choice = conf.active_config.ui_frontend
  local has_telescope = pcall(require, "telescope")
  local has_fzf = pcall(require, "fzf-lua")
  
  -- ★★★ これが、最後の、そして、最も重要な、最後の砦です ★★★
  -- 外部コマンド `fd` が存在するかどうかを、最初に一度だけチェックする
  local has_fd = vim.fn.executable("fd") == 1

  -- ユーザーが明示的に "telescope" を選んだ場合
  if choice == "telescope" then
    if has_telescope and has_fd then
      return require("UCMUI.frontend.telescope")
    else
      logger.warn("Telescope or fd is not available. Falling back to native UI.")
      return require("UCMUI.frontend.native")
    end
  end

  -- ユーザーが明示的に "fzf-lua" を選んだ場合
  if choice == "fzf-lua" then
    if has_fzf and has_fd then
      return require("UCMUI.frontend.fzf_lua")
    else
      logger.warn("fzf-lua or fd is not available. Falling back to native UI.")
      return require("UCMUI.frontend.native")
    end
  end

  -- "native" が選ばれた場合
  if choice == "native" then
    return require("UCMUI.frontend.native")
  end

  -- "auto" モード (デフォルト)
  if has_telescope and has_fd then
    return require("UCMUI.frontend.telescope")
  end
  if has_fzf and has_fd then
    return require("UCMUI.frontend.fzf_lua")
  end
  return require("UCMUI.frontend.native")
end

-- (この下の関数たちは、変更ありません)
function M.select_parent_class(choices, on_select)
  get_backend().select_parent_class(choices, on_select)
end

function M.select_code_directory(on_select)
  get_backend().select_code_directory(on_select)
end

function M.select_cpp_file(on_select)
  get_backend().select_cpp_file(on_select)
end

return M
