-- lua/UCM/provider/class_pair.lua
local cmd_core = require("UCM.cmd.core")
local log = require("UCM.logger")

local M = {}

---
-- 'ucm.get_class_pair' request handler
-- @param opts table { file_path = "..." }
-- @return table|nil { h = "...", cpp = "...", class_name = "..." }
function M.request(opts)
  local file_path = opts.file_path
  if not file_path then
    log.get().warn("Provider 'ucm.get_class_pair': No file_path provided.")
    return nil
  end

  log.get().debug("Provider 'ucm.get_class_pair' called for: %s", file_path)

  -- UCMのコアロジックを使ってペアを解決
  local result, err = cmd_core.resolve_class_pair(file_path)
  
  if not result then
    log.get().debug("Failed to resolve class pair: %s", err)
    return nil
  end

  return result
end

return M
