-- lua/UCMUI/ui/delete.-- lua/UCMUI/ui/delete.lua

local frontend = require("UCMUI.frontend")
local api = require("UCM.api")
local logger = require("UCM.logger")

local M = {}

local function on_cancel(result, opts)
  logger.info("Operation canceled by user.")
  if opts.on_cancel then
     opts.on_cancel(result)
  end
end

function M.run(opts)
  opts = opts or {}

  -- この関数が、ファイルが選択された後の、共通の処理フロー
  local function start_delete_flow(selected_file)
    api.delete_class({
      file_path = selected_file,
    })
  end

  if opts.file_path then
    -- もし、Neo-treeなどから、すでにファイルパスが与えられていたら...
    -- ...ファイル選択UIを、スキップする！
    start_delete_flow(opts.file_path)
  else
    -- そうでなければ、ユーザーにファイルを選んでもらう
    frontend.select_cpp_file(function(selected_file)
      if not selected_file then
        return on_cancel("canceled", opts)
      end
      start_delete_flow(selected_file)
    end)
  end
end

return M
