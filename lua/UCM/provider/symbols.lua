local outline_logic = require("UCM.logic.outline")
local log = require("UCM.logger")

local M = {}

function M.request(opts)
  local file_path = opts.file_path
  if not file_path then
    return nil -- エラーならnil
  end

  local symbols = outline_logic.get_outline(file_path)
  
  -- ★重要: ここは symbols (テーブル) だけを返してください
  -- UNLの仕組みが自動的に (true, symbols) として呼び出し元に返します
  return symbols
end

return M
