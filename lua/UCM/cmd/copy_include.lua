local unl_picker = require("UNL.backend.picker")
local unl_picker = require("UNL.picker")
local unl_finder = require("UNL.finder")
local unl_api = require("UNL.api")
local log = require("UCM.logger")
local fs = require("vim.fs")
local cmd_core = require("UCM.cmd.core")

local M = {}

local function copy_to_clipboard(text)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify(string.format("Copied: %s", text), vim.log.levels.INFO)
  log.get().info("Copied include path: %s", text)
end

local function resolve_and_copy(file_path)
  -- ★修正: .cppファイルの場合は、対になるヘッダーファイルを検索して対象を切り替える
  if file_path:match("%.cpp$") then
    local pair, _ = cmd_core.resolve_class_pair(file_path)
    if pair and pair.h then
      log.get().debug("Switched copy target from .cpp to .h: %s", pair.h)
      file_path = pair.h
    else
      log.get().warn("Could not find paired header for .cpp file. Result might be incorrect.")
    end
  end

  local module_info = unl_finder.module.find_module(file_path)
  local relative_path = nil
  
  if module_info then
    local module_root = module_info.root
    -- 検索順序。Privateフォルダ内のヘッダーも含めるため Private も検索対象
    local search_dirs = { "Public", "Classes", "Private" }
    
    for _, dir in ipairs(search_dirs) do
      local base = fs.joinpath(module_root, dir)
      -- baseパスが含まれているか確認 (正規化パスでの比較が理想だが簡易判定)
      if file_path:find(base, 1, true) then
         -- baseの長さ + パス区切り文字分(1) + 1 から末尾までを取得
         relative_path = file_path:sub(#base + 2)
         break
      end
    end
  end

  -- モジュール構造から解決できなかった場合のフォールバック（ファイル名のみ）
  if not relative_path then
    relative_path = vim.fn.fnamemodify(file_path, ":t")
  end

  -- #include 形式に整形
  local include_str = string.format('#include "%s"', relative_path)
  copy_to_clipboard(include_str)
end

local function get_header_search_cmd()
  local extensions = { "h", "hpp", "inl" }
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

function M.run(opts)
  opts = opts or {}
  local logger = log.get()

  if opts.file_path then
    resolve_and_copy(opts.file_path)
    return
  end

  if opts.has_bang then
    logger.debug("Attempting to fetch class list from UEP...")
    
    local uep_available = false
    local header_details = nil

    if unl_api.provider then
        local req_ok, res = unl_api.provider.request("uep.get_project_classes", { 
            scope = "Full", 
            logger_name = "UCM" 
        })
        if req_ok and res then
            uep_available = true
            header_details = res
        end
    end

    if uep_available then
        local items = {}
        for file_path, details in pairs(header_details) do
          if details.classes then
            for _, cls in ipairs(details.classes) do
              table.insert(items, {
                display = cls.class_name,
                value = file_path,
                filename = file_path,
                kind = "Class"
              })
            end
          end
        end
        table.sort(items, function(a,b) return a.display < b.display end)

        unl_picker.open({
          kind = "ucm_copy_include",
          title = "Select Class to Copy #include",
          items = items,
          conf = require("UNL.config").get("UCM"),
          preview_enabled = true,
          on_submit = function(path)
            if path then resolve_and_copy(path) end
          end
        })
        return
    end

    logger.info("UEP not available. Falling back to simple header file search.")
    
    unl_picker.open({
        title = "Select Header File (Fallback Mode)",
        conf = require("UNL.config").get("UCM"),
        logger_name = "UCM",
        preview_enabled = true,
        exec_cmd = get_header_search_cmd(),
        on_submit = function(file_path)
            if file_path then resolve_and_copy(file_path) end
        end
    })
    return
  end

  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file and current_file ~= "" then
    resolve_and_copy(current_file)
  else
    logger.warn("No file in current buffer.")
  end
end

return M


