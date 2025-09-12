-- lua/UCM/cmd/core.lua (UNLベースにリファクタリング)

local unl_finder = require("UNL.finder") -- ★ 変更点: UNLのファインダーを利用
local selectors = require("UCM.selector")
local log = require("UCM.logger")
local fs = require("vim.fs")

local M = {}

---
-- 'new'コマンドのために、起点ディレクトリからコンテキストを解決する
-- @param target_dir string
-- @return table|nil, string
function M.resolve_creation_context(target_dir)
  local absolute_dir = fs.normalize(target_dir)

  local module_root = unl_finder.module.find_module_root(absolute_dir)
  if not module_root then
    return nil, "Could not find a .build.cs to determine module context."
  end

  local build_cs_path
  for name, _ in vim.fs.dir(module_root) do
    if name:match("%.[Bb]uild%.cs$") then
      build_cs_path = name
      break
    end
  end
  if not build_cs_path then
    return nil, "Found module root, but failed to find .build.cs file inside."
  end

  --- ★★★ ここからが修正箇所 ★★★
  -- ".Build.cs" または ".build.cs" を空文字列に置換して、モジュール名だけを抽出する
  local module_name = build_cs_path:gsub("%.[Bb]uild%.cs$", "")
  --- ★★★ 修正箇所ここまで ★★★

  local module_info = {
    root = module_root,
    name = module_name,
  }

  local header_dir, source_dir = selectors.folder.resolve_locations(absolute_dir)

  return {
    module = module_info,
    header_dir = header_dir,
    source_dir = source_dir,
  }
end

---
-- 'switch', 'delete', 'rename'のために、既存のクラスペアを解決する
-- @param file_path string
-- @return table|nil, string
function M.resolve_class_pair(file_path)
  local absolute_file = fs.normalize(file_path)

  if vim.fn.filereadable(absolute_file) ~= 1 then
    return nil, "Input file does not exist: " .. absolute_file
  end

  -- resolve_creation_contextは既にリファクタリング済みなので、そのまま利用できる
  local context, err = M.resolve_creation_context(fs.dirname(absolute_file))
  if not context then
    return nil, err
  end

  local class_name = vim.fn.fnamemodify(absolute_file, ":t:r")
  local result = {
    h = fs.normalize(fs.joinpath(context.header_dir, class_name .. ".h")),
    cpp = fs.normalize(fs.joinpath(context.source_dir, class_name .. ".cpp")),
    class_name = class_name,
    is_header_input = absolute_file:match("%.h$") and true or false,
    module = context.module,
  }

  if vim.fn.filereadable(result.h) ~= 1 then result.h = nil end
  if vim.fn.filereadable(result.cpp) ~= 1 then result.cpp = nil end

  if not result.h and not result.cpp then
    return nil, "Could not resolve any existing class files for: " .. class_name
  end

  return result
end
-- @param base_path string|nil 検索を開始する起点ディレクトリ。nilならcwd。
function M.get_fd_directory_cmd(base_path)
  local full_path_regex = ".*[\\\\/](Source|Plugins)[\\\\/].*"
  local excludes = { "Intermediate", "Binaries", "Saved" }

  local fd_cmd = { "fd" }
  
  -- ★★★ ここからが修正箇所 ★★★
  -- base_path が指定されていれば、それをfdの検索パス引数として追加する
  if base_path and base_path ~= "" then
    table.insert(fd_cmd, ".") -- パターンとしてカレントを指定
    table.insert(fd_cmd, base_path) -- 検索ベースパスを指定
  end
  -- ★★★ 修正箇所ここまで ★★★
  
  table.insert(fd_cmd, "--regex")
  table.insert(fd_cmd, full_path_regex)
  table.insert(fd_cmd, "--full-path")
  table.insert(fd_cmd, "--type")
  table.insert(fd_cmd, "d")
  table.insert(fd_cmd, "--path-separator")
  table.insert(fd_cmd, "/")
  
  for _, dir in ipairs(excludes) do
    table.insert(fd_cmd, "--exclude")
    table.insert(fd_cmd, dir)
  end
  return fd_cmd
end

function M.get_fd_files_cmd()
  local extensions = {
    "cpp",
    "h",
    "hpp",
    "inl",
  }

  local full_path_regex = ".*[\\\\/](Source|Plugins)[\\\\/].*\\.(" .. table.concat(extensions, "|") .. ")$"
  local excludes = { "Intermediate", "Binaries", "Saved" }

  local fd_cmd = {
    "fd",
    "--regex", full_path_regex,
    "--full-path",
    "--type", "f",
    "--path-separator", "/",
    -- "--absolute-path",
  } 

  for _, dir in ipairs(excludes) do
    table.insert(fd_cmd, "--exclude")
    table.insert(fd_cmd, dir)
  end
  return fd_cmd
end


return M
