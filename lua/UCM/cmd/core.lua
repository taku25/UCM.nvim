-- lua/UCM/cmd/core.lua

local unl_finder = require("UNL.finder")
local unl_path = require("UNL.path")
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
-- @param on_complete function|nil (table|nil, string|nil) - もしnilなら同期的にFSから検索する
function M.resolve_class_pair(file_path, on_complete)
  local absolute_file = fs.normalize(file_path)
  if vim.fn.filereadable(absolute_file) ~= 1 then
    local err = "Input file does not exist: " .. absolute_file
    if on_complete then return on_complete(nil, err) else return nil, err end
  end

  local class_name = vim.fn.fnamemodify(absolute_file, ":t:r")
  local is_header_input = absolute_file:match("%.h$") and true or false

  -- 非同期コールバックがない場合は、同期的にFSから探す (互換性のため)
  if not on_complete then
    return M.resolve_class_pair_fallback_sync(file_path)
  end

  local unl_api = require("UNL.api")
  
  -- DBからクラス名で検索 (非同期)
  -- 注意: get_classes の第一引数は現在 opts テーブル
  unl_api.db.find_class_by_name(class_name, function(cls)
    if not cls then
        -- DBになければファイル名ベースでフォールバック
        return M.resolve_class_pair_fallback(file_path, on_complete)
    end

    -- 対になるファイルを探す
    local h_path = is_header_input and absolute_file or nil
    local cpp_path = not is_header_input and absolute_file or nil

    if is_header_input then
        -- ヘッダー入力時、ソースを探す
        local target_cpp = class_name .. ".cpp"
        unl_api.db.search_files(target_cpp, function(files)
            if files then
                for _, f in ipairs(files) do
                    -- モジュール名が一致するものを優先
                    if f.module_name == cls.module_name or f.path:find(cls.module_root, 1, true) then
                        cpp_path = f.path
                        break
                    end
                end
            end
            on_complete({
                h = h_path,
                cpp = cpp_path,
                class_name = class_name,
                is_header_input = is_header_input,
                module = { name = cls.module_name, root = cls.module_root }
            })
        end)
    else
        -- ソース入力時、ヘッダーを探す
        local target_h = class_name .. ".h"
        unl_api.db.search_files(target_h, function(files)
            if files then
                for _, f in ipairs(files) do
                    if f.module_name == cls.module_name or f.path:find(cls.module_root, 1, true) then
                        h_path = f.path
                        break
                    end
                end
            end
            on_complete({
                h = h_path,
                cpp = cpp_path,
                class_name = class_name,
                is_header_input = is_header_input,
                module = { name = cls.module_name, root = cls.module_root }
            })
        end)
    end
  end)
end

-- 同期版フォールバック (UNXなどの同期コンテキスト用)
function M.resolve_class_pair_fallback_sync(file_path)
  local absolute_file = fs.normalize(file_path)
  local context, err = M.resolve_creation_context(fs.dirname(absolute_file))
  if not context then return nil, err end

  local class_name = vim.fn.fnamemodify(absolute_file, ":t:r")
  local is_header_input = absolute_file:match("%.h$") and true or false
  local found_h = is_header_input and absolute_file or nil
  local found_cpp = not is_header_input and absolute_file or nil

  if is_header_input then
    for _, dir in ipairs(context.source_dirs) do
      local p = fs.normalize(fs.joinpath(dir, class_name .. ".cpp"))
      if vim.fn.filereadable(p) == 1 then found_cpp = p; break end
    end
  else
    for _, dir in ipairs(context.header_dirs) do
      local p = fs.normalize(fs.joinpath(dir, class_name .. ".h"))
      if vim.fn.filereadable(p) == 1 then found_h = p; break end
    end
  end

  if not found_h and not found_cpp then return nil, "Could not resolve pair sync" end

  return {
    h = found_h,
    cpp = found_cpp,
    class_name = class_name,
    is_header_input = is_header_input,
    module = context.module,
  }
end

-- 非同期版フォールバック
function M.resolve_class_pair_fallback(file_path, on_complete)
  local res, err = M.resolve_class_pair_fallback_sync(file_path)
  if on_complete then on_complete(res, err) end
  return res, err
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
    "--regex",
    full_path_regex,
    "--full-path",
    "--type",
    "f",
    "--path-separator",
    "/",
  }

  for _, dir in ipairs(excludes) do
    table.insert(fd_cmd, "--exclude")
    table.insert(fd_cmd, dir)
  end
  return fd_cmd
end

function M.get_relative_include_path(absolute_path)
  if not absolute_path then
    return nil
  end
  local normalized_path = absolute_path:gsub("\\", "/")
  local match = normalized_path:match("/Source/[^/]+/[Pp]ublic/(.+)")
    or normalized_path:match("/Source/[^/]+/[Pp]rivate/(.+)")
    or normalized_path:match("/Plugins/[^/]+/Source/[^/]+/[Pp]ublic/(.+)")
    or normalized_path:match("/Plugins/[^/]+/Source/[^/]+/[Pp]rivate/(.+)")
  if match then
    return match
  end
  match = normalized_path:match("/Source/[^/]+/(.+)") or normalized_path:match("/Plugins/[^/]+/Source/[^/]+/(.+)")
  if match then
    return match
  end
  return nil
end

return M
