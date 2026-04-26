-- lua/UCM/cmd/insert_include.lua
-- 現在のバッファに #include 行を自動挿入する

local unl_picker = require("UNL.picker")
local unl_finder = require("UNL.finder")
local unl_api = require("UNL.api")
local log = require("UCM.logger")
local fs = require("vim.fs")
local cmd_core = require("UCM.cmd.core")

local M = {}

-- ファイルパスから #include 文字列を解決する
local function resolve_include_str(file_path)
  if file_path:match("%.cpp$") then
    local pair = cmd_core.resolve_class_pair(file_path)
    if pair and pair.h then file_path = pair.h end
  end

  local module_info = unl_finder.module.find_module(file_path)
  local relative_path = nil

  if module_info then
    local module_root = module_info.root
    for _, dir in ipairs({ "Public", "Classes", "Private" }) do
      local base = fs.joinpath(module_root, dir)
      if file_path:find(base, 1, true) then
        relative_path = file_path:sub(#base + 2)
        break
      end
    end
  end

  if not relative_path then
    relative_path = vim.fn.fnamemodify(file_path, ":t")
  end

  return string.format('#include "%s"', relative_path:gsub("\\", "/"))
end

-- バッファに #include 行を挿入する (最後の #include の直後)
local function insert_into_buffer(bufnr, include_str)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- 既に同じ include がある場合は何もしない
  for _, line in ipairs(lines) do
    if line == include_str then
      log.get().info("Already included: %s", include_str)
      return
    end
  end

  -- 最後の #include 行を探す
  local last_include_line = -1
  for i, line in ipairs(lines) do
    if line:match("^%s*#include") then
      last_include_line = i
    end
  end

  local insert_at
  if last_include_line >= 1 then
    insert_at = last_include_line  -- 0-indexed で last_include_line は最後の #include の次
  else
    -- #include が全くない場合はファイル先頭
    insert_at = 0
  end

  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { include_str })
  log.get().info("Inserted: %s (line %d)", include_str, insert_at + 1)
end

-- ファイル選択後に挿入を実行する
local function do_insert(target_header_path)
  if not target_header_path or target_header_path == "" then return end
  local include_str = resolve_include_str(target_header_path)
  local bufnr = vim.api.nvim_get_current_buf()
  insert_into_buffer(bufnr, include_str)
end

function M.execute(opts)
  opts = opts or {}
  local logger = log.get()

  -- 引数でファイルパスが指定されていれば直接挿入
  if opts.file_path and opts.file_path ~= "" then
    do_insert(opts.file_path)
    return
  end

  -- UEP 経由でクラスリストを取得してピッカー表示
  local uep_ok = false
  if unl_api.provider then
    local req_ok, header_details = unl_api.provider.request("uep.get_project_classes", {
      scope = "Full",
      logger_name = "UCM",
    })
    if req_ok and header_details then
      uep_ok = true
      local items = {}
      for file_path, details in pairs(header_details) do
        if details.classes then
          for _, cls in ipairs(details.classes) do
            table.insert(items, {
              display = cls.class_name or cls.name or file_path,
              value = file_path,
              filename = file_path,
            })
          end
        end
      end
      table.sort(items, function(a, b) return a.display < b.display end)

      unl_picker.open({
        kind = "ucm_insert_include",
        title = "  Insert #include",
        items = items,
        conf = require("UNL.config").get("UCM"),
        preview_enabled = true,
        on_submit = function(selected)
          if selected then
            local path = type(selected) == "string" and selected or selected.value
            do_insert(path)
          end
        end,
      })
      return
    end
  end

  -- フォールバック: fd でヘッダーファイル一覧
  if not uep_ok then
    logger.info("UEP not available, falling back to header file search.")
    local extensions = { "h", "hpp", "inl" }
    local regex = ".*[\\\\/](Source|Plugins)[\\\\/].*\\.(" .. table.concat(extensions, "|") .. ")$"
    local fd_cmd = { "fd", "--regex", regex, "--full-path", "--type", "f", "--path-separator", "/" }
    for _, ex in ipairs({ "Intermediate", "Binaries", "Saved" }) do
      table.insert(fd_cmd, "--exclude"); table.insert(fd_cmd, ex)
    end

    unl_picker.open({
      title = "  Insert #include (select header)",
      conf = require("UNL.config").get("UCM"),
      logger_name = "UCM",
      preview_enabled = true,
      exec_cmd = fd_cmd,
      on_submit = function(file_path)
        if file_path then do_insert(file_path) end
      end,
    })
  end
end

return M
