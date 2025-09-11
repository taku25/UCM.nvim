-- lua/UCM/provider/rename.lua

local ucm_api = require("UCM.api")
local log = require("UNL.logging").get("UCM.nvim")

local M = {}

---
-- 'ucm.class.rename' capability のための request ハンドラ
-- @param opts table クラスのリネームに必要なオプション
--   - source_path (string): リネーム対象のファイルパス
--   - new_class_name (string): 新しいクラス名
--   - (その他、UCM.api.rename が要求するオプション)
-- @return boolean, any: 成功時は true と結果、失敗時は false とエラーメッセージ
function M.request(opts)
  log.debug("Provider 'ucm.class.rename' called with opts: %s", vim.inspect(opts))

  local ok, result = pcall(ucm_api.rename, opts)
  if not ok then
    log.error("Provider 'ucm.class.rename' failed: %s", tostring(result))
    return false, result
  end

  log.info("Provider 'ucm.class.rename' successfully executed.")
  return true, result
end

return M
