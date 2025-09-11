-- lua/UCM/provider/delete.lua

local ucm_api = require("UCM.api")

local M = {}

---
-- 'ucm.class.delete' capability のための request ハンドラ
-- @param opts table クラス削除に必要なオプション
--   - class_path (string): 削除対象のヘッダー/ソースファイルのパス
--   - (その他、UCM.api.delete が要求するオプション)
-- @return boolean, any: 成功時は true と結果、失敗時は false とエラーメッセージ
function M.request(opts)

  local log = require("UNL.logging").get("UCM")
  log.debug("Provider 'ucm.class.delete' called with opts: %s", vim.inspect(opts))

  local ok, result = pcall(ucm_api.delete, opts)
  if not ok then
    log.error("Provider 'ucm.class.delete' failed: %s", tostring(result))
    return false, result
  end

  log.info("Provider 'ucm.class.delete' successfully executed.")
  return true, result
end

return M
