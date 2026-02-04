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
  local logger = log.get()
  local absolute_file = fs.normalize(file_path)
  if vim.fn.filereadable(absolute_file) ~= 1 then
    local err = "Input file does not exist: " .. absolute_file
    if on_complete then return on_complete(nil, err) else return nil, err end
  end

  local class_name = vim.fn.fnamemodify(absolute_file, ":t:r")
  local is_header_input = absolute_file:match("%.h$") and true or false
  
  logger.info("Resolving pair for: %s (Class: %s)", absolute_file, class_name)

  -- 非同期コールバックがない場合は、同期的にFSから探す
  if not on_complete then
    return M.resolve_class_pair_fallback_sync(file_path)
  end

  local unl_api = require("UNL.api")
  
  -- 1. DBからファイル情報を取得
  unl_api.db.get_file_symbols(absolute_file, function(symbols)
    local cls = (symbols and #symbols > 0) and symbols[1] or nil
    
    if cls and cls ~= vim.NIL and cls.module_name then
        logger.info("Found class in DB: %s (Module: %s)", cls.name, cls.module_name)
        return M.resolve_pair_in_module(cls.module_name, class_name, absolute_file, is_header_input, on_complete)
    end

    -- 2. DBに見つからない場合、ファイル名から全DB検索
    logger.info("Class not in DB or no module info. Searching by filename...")
    local target_file_name = is_header_input and (class_name .. ".cpp") or (class_name .. ".h")
    
    unl_api.db.search_files(target_file_name, function(files)
        if files and #files > 0 then
            for _, f in ipairs(files) do
                if f.filename == target_file_name then
                    logger.info("Found pair via global filename search: %s", f.path)
                    return on_complete({
                        h = is_header_input and absolute_file or f.path,
                        cpp = not is_header_input and absolute_file or f.path,
                        class_name = class_name, is_header_input = is_header_input,
                        module = { name = f.module_name }
                    })
                end
            end
        end
        
        -- 3. それでもダメならFSフォールバック
        logger.info("DB search failed. Falling back to File System search...")
        local res, err = M.resolve_class_pair_fallback_sync(file_path)
        if res then
            logger.info("Found pair via File System fallback: %s", is_header_input and res.cpp or res.h)
            on_complete(res)
        else
            logger.warn("All resolution methods failed: %s", tostring(err))
            on_complete(nil, err)
        end
    end)
  end)
end

-- ヘルパー: 特定のモジュール内でペアを解決する
function M.resolve_pair_in_module(module_name, class_name, absolute_file, is_header_input, on_complete)
    local unl_api = require("UNL.api")
    local target_ext = is_header_input and ".cpp" or ".h"
    local target_file = class_name .. target_ext
    
    unl_api.db.search_files_in_modules({ module_name }, target_file, 10, function(files)
        local pair_path = nil
        if files then
            for _, f in ipairs(files) do
                if vim.fn.fnamemodify(f.file_path, ":t") == target_file then
                    pair_path = f.file_path; break
                end
            end
            if not pair_path and #files > 0 then pair_path = files[1].file_path end
        end
        
        if pair_path then
            on_complete({
                h = is_header_input and absolute_file or pair_path,
                cpp = not is_header_input and absolute_file or pair_path,
                class_name = class_name,
                is_header_input = is_header_input,
                module = { name = module_name }
            })
        else
            -- DBで見つからなかった場合はFSフォールバック
            M.resolve_class_pair_fallback(absolute_file, on_complete)
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
