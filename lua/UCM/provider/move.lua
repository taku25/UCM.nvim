-- lua/UCM/provider/move.lua

local ucm_api = require("UCM.api")

local M = {}

---
-- 'ucm.class.move' capability のための request ハンドラ
-- @param opts table クラス移動/リネームに必要なオプション
--   - source_path (string): 移動元のファイルパス
--   - target_path (string): 移動先のファイルパス
--   - (その他、UCM.api.move が要求するオプション)
-- @return boolean, any: 成功時は true と結果、失敗時は false とエラーメッセージ
function M.request(opts)
  local log = require("UNL.logging").get("UCM")
  log.debug("Provider 'ucm.class.move' called with opts: %s", vim.inspect(opts))

  local ok, result = pcall(ucm_api.move_class, opts)
  if not ok then
    log.error("Provider 'ucm.class.move' failed: %s", tostring(result))
    return false, result
  end

  log.info("Provider 'ucm.class.move' successfully executed.")
  return true, result
end

return M
