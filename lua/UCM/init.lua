-- lua/UCM/init.lua (新しいエントリーポイント)
local unl_log = require("UNL.logging")
local ucm_defaults = require("UCM.config.defaults")

local backend_progress = require("UNL.backend.progress")
local backend_picker = require("UNL.backend.picker")
local backend_filer = require("UNL.backend.filer")
local M = {}

function M.setup(user_opts)
  -- この一行で、UNLに "UCM" プラグインを登録し、
  -- 設定とロガーの両方を初期化します。
  unl_log.setup("UCM", ucm_defaults, user_opts or {})

  backend_progress.load_providers()
  backend_picker.load_providers()
  backend_filer.load_providers() -- これを追加

  local log = unl_log.get("UCM")
  if log then
    log.debug("UCM.nvim setup complete.")
  end

end

return M
