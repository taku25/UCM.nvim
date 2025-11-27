-- lua/UCM/cmd/core.lua

local unl_finder = require("UNL.finder")
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

  local module_name = vim.fn.fnamemodify(build_cs_path, ":r:r")

  local module_info = {
    root = module_root,
    name = module_name,
  }

  -- ★変更: リストを受け取る
  local header_dirs, source_dirs = selectors.folder.resolve_locations(absolute_dir)

  return {
    module = module_info,
    -- 新規作成用には、リストの先頭（最も優先度の高いルール）を採用する
    header_dir = header_dirs[1],
    source_dir = source_dirs[1],
    -- 検索用に全候補も保持しておく
    header_dirs = header_dirs,
    source_dirs = source_dirs,
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

  local context, err = M.resolve_creation_context(fs.dirname(absolute_file))
  if not context then
    return nil, err
  end

  local class_name = vim.fn.fnamemodify(absolute_file, ":t:r")
  local is_header_input = absolute_file:match("%.h$") and true or false

  local found_h = nil
  local found_cpp = nil

  -- ★変更: ヘッダーファイルの探索 (候補リスト順)
  if is_header_input then
      found_h = absolute_file
  else
      for _, dir in ipairs(context.header_dirs) do
          local p = fs.normalize(fs.joinpath(dir, class_name .. ".h"))
          if vim.fn.filereadable(p) == 1 then
              found_h = p
              break -- 見つかったら終了
          end
      end
  end

  -- ★変更: ソースファイルの探索 (候補リスト順)
  if not is_header_input then
      found_cpp = absolute_file
  else
      for _, dir in ipairs(context.source_dirs) do
          local p = fs.normalize(fs.joinpath(dir, class_name .. ".cpp"))
          if vim.fn.filereadable(p) == 1 then
              found_cpp = p
              break -- 見つかったら終了
          end
      end
  end

  if not found_h and not found_cpp then
    return nil, "Could not resolve any existing class files for: " .. class_name
  end

  return {
    h = found_h,
    cpp = found_cpp,
    class_name = class_name,
    is_header_input = is_header_input,
    module = context.module,
  }
end

function M.get_fd_directory_cmd(base_path)
  local full_path_regex = ".*[\\\\/](Source|Plugins)[\\\\/].*"
  local excludes = { "Intermediate", "Binaries", "Saved" }

  local fd_cmd = { "fd" }
  
  if base_path and base_path ~= "" then
    table.insert(fd_cmd, ".") 
    table.insert(fd_cmd, base_path) 
  end
  
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
  local extensions = { "cpp", "h", "hpp", "inl" }
  local full_path_regex = ".*[\\\\/](Source|Plugins)[\\\\/].*\\.(" .. table.concat(extensions, "|") .. ")$"
  local excludes = { "Intermediate", "Binaries", "Saved" }

  local fd_cmd = {
    "fd",
    "--regex", full_path_regex,
    "--full-path",
    "--type", "f",
    "--path-separator", "/",
  } 

  for _, dir in ipairs(excludes) do
    table.insert(fd_cmd, "--exclude")
    table.insert(fd_cmd, dir)
  end
  return fd_cmd
end

function M.get_relative_include_path(absolute_path)
    if not absolute_path then return nil end
    local normalized_path = absolute_path:gsub("\\", "/")
    local match = normalized_path:match("/Source/[^/]+/[Pp]ublic/(.+)")
               or normalized_path:match("/Source/[^/]+/[Pp]rivate/(.+)")
               or normalized_path:match("/Plugins/[^/]+/Source/[^/]+/[Pp]ublic/(.+)")
               or normalized_path:match("/Plugins/[^/]+/Source/[^/]+/[Pp]rivate/(.+)")
    if match then return match end
    match = normalized_path:match("/Source/[^/]+/(.+)")
         or normalized_path:match("/Plugins/[^/]+/Source/[^/]+/(.+)")
    if match then return match end
    return nil
end

return M
