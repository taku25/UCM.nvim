-- lua/UCM/provider/new.lua

local ucm_api = require("UCM.api")
local log = require("UNL.logging").get("UCM.nvim")

local M = {}

---
-- 'ucm.class.new' capability のための request ハンドラ
-- @param opts table クラス作成に必要なオプション
--   - template (string): 使用するテンプレート名 (例: "Actor")
--   - class_name (string): 作成するクラス名
--   - (その他、UCM.api.new が要求するオプション)
-- @return boolean, any: 成功時は true と結果、失敗時は false とエラーメッセージ
function M.request(opts)
  log.debug("Provider 'ucm.class.new' called with opts: %s", vim.inspect(opts))

  -- ucm_api.new に処理を委譲する
  -- ucm_api.new が pcall で保護されているか、
  -- もしくはここで pcall を使うのが望ましい
  local ok, result = pcall(ucm_api.new, opts)
  if not ok then
    log.error("Provider 'ucm.class.new' failed: %s", tostring(result))
    return false, result -- エラーメッセージをそのまま返す
  end

  log.info("Provider 'ucm.class.new' successfully executed.")
  return true, result
end

return M
