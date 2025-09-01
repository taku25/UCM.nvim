-- lua/UCM/init.lua (新しいエントリーポイント)
local unl_log = require("UNL.logging")
local ucm_defaults = require("UCM.config.defaults")

local M = {}

function M.setup(user_opts)
  -- この一行で、UNLに "UCM" プラグインを登録し、
  -- 設定とロガーの両方を初期化します。
  unl_log.setup("UCM", ucm_defaults, user_opts or {})
  
  local log = unl_log.get("UCM")
  if log then
    log.debug("UCM.nvim setup complete.")
  end

end

return M
