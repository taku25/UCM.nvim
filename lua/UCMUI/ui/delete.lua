-- lua/UCMUI/ui/delete.-- lua/UCMUI/ui/delete.lua

local frontend = require("UCMUI.frontend")
local api = require("UCM.api")
local logger = require("UCM.logger")

local M = {}

function M.create(opts, on_complete)
  opts = opts or {}

  -- この関数が、ファイルが選択された後の、共通の処理フロー
  local function start_delete_flow(selected_file)
    api.delete_class({ file_path = selected_file }, on_complete)
  end

  -- ★★★ これが、あなたの最後の、そして、最も美しい、哲学です ★★★
  if opts.file_path then
    -- もし、Neo-treeなどから、すでにファイルパスが与えられていたら...
    -- ...ファイル選択UIを、スキップする！
    start_delete_flow(opts.file_path)
  else
    -- そうでなければ、ユーザーにファイルを選んでもらう
    frontend.select_cpp_file(function(selected_file)
      if not selected_file then
        return on_complete(false, "canceled")
      end
      start_delete_flow(selected_file)
    end)
  end
end

return M
