-- lua/UCMUI/ui/rename.lua

local frontend = require("UCMUI.frontend")
local api = require("UCM.api")
local logger = require("UCM.logger")

local M = {}

function M.create()
  -- Step 1: どのファイルをリネームするか、ユーザーに選ばせる
  frontend.select_cpp_file(function(selected_file)
    if not selected_file then
      logger.info("Rename operation canceled.")
      return
    end

    -- ★★★ これが、あなたの最後の、そして、最も美しい、哲学です ★★★
    -- UIレイヤーは、重い解決処理は行わない。
    -- ただ、ファイル名から、電光石火の速さで、古い名前を取得するだけ。
    local old_name = vim.fn.fnamemodify(selected_file, ":t:r")

    -- Step 2: あなたの完璧なUX設計で、vim.ui.inputを呼び出す
    vim.ui.input({
      prompt = "Rename: " .. old_name .. " ->",
      default = old_name,
    }, function(new_name)
      if not new_name or new_name == "" or new_name == old_name then
        logger.info("Rename operation canceled.")
        return
      end

      -- Step 3: 最後の確認と実行は、賢いcmdレイヤーに、すべてを委ねる
      api.rename_class(
        { file_path = selected_file, new_class_name = new_name },
        function(ok, result)
          -- (結果の表示は、plugin/UCM.luaのコールバックが担当)
        end
      )
    end)
  end)
end

return M
