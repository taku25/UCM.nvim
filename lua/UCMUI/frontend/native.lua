-- lua/UCMUI/frontend/native.lua

local M = {}

function M.select_parent_class(choices, on_select)
  vim.ui.select(choices, { prompt = "Select Parent Class" }, on_select)
end

function M.select_code_directory(on_select)
  vim.ui.input({ prompt = "Enter Target Directory (relative path):", default = "./" }, function(dir)
    if not dir or dir == "" then on_select(nil) else on_select(dir) end
  end)
end

function M.select_cpp_file(on_select)
  vim.ui.input({
    prompt = "Enter C++ File Path (.h/.cpp):",
    completion = "file", -- ファイルパス補完を有効にする
  }, function(file_path)
    if not file_path or file_path == "" then
      on_select(nil)
    else
      on_select(file_path)
    end
  end)
end

return M
