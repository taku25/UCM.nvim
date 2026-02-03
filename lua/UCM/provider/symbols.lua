local outline_logic = require("UCM.logic.outline")
local log = require("UCM.logger")

local M = {}

function M.request(opts, on_complete)
  local file_path = opts.file_path or opts[1] -- 念のため配列形式も考慮
  
  if not file_path or file_path == "" then
    log.get().error("UCM symbols provider: file_path is missing. (Opts: %s)", vim.inspect(opts))
    if on_complete then on_complete(false, "No file path") end
    return
  end

  if not on_complete then
    log.get().error("UCM symbols provider: 'on_complete' is nil for %s. (Opts: %s)", file_path, vim.inspect(opts))
    return
  end

  log.get().debug("UCM symbols provider: Fetching outline for %s", file_path)
  outline_logic.get_outline(file_path, function(symbols)
    if not symbols then
        log.get().warn("UCM symbols provider: get_outline returned nil for %s", file_path)
    end
    on_complete(true, symbols or {})
  end)
end

return M
