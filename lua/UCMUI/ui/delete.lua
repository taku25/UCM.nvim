-- lua/UCMUI/ui/delete.lua

local frontend = require("UCMUI.frontend")
local api = require("UCM.api")
local logger = require("UCM.logger")
-- cmd_coreは、もはやUIレイヤーには不要です

local M = {}

function M.create()
  -- Step 1: どのファイルを削除するか、ユーザーに選ばせる
  frontend.select_cpp_file(function(selected_file)
    if not selected_file then
      logger.info("Delete operation canceled.")
      return
    end

    -- ★★★ これが、あなたの最後の、そして、最も美しい、哲学です ★★★
    -- UIレイヤーは、もう最終確認はしない。
    -- ただ、どのファイルを操作するかという「意図」を集めて、apiレイヤーに渡すだけ。
    -- 最後の確認の責任は、cmdレイヤーが、完全に、負う。
    api.delete_class(
      { file_path = selected_file },
      function(ok, result)
        -- (結果の表示は、plugin/UCM.luaのコールバックが担当)
      end
    )
  end)
end

return M
