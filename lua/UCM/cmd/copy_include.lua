-- lua/UCM/cmd/copy_include.lua

local unl_picker = require("UNL.backend.picker")
local unl_finder = require("UNL.finder")
local unl_api = require("UNL.api")
local log = require("UCM.logger")
local fs = require("vim.fs")

local M = {}

-- クリップボードコピー
local function copy_to_clipboard(text)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify(string.format("Copied: %s", text), vim.log.levels.INFO)
  log.get().info("Copied include path: %s", text)
end

-- パス解決ロジック
local function resolve_and_copy(file_path)
  -- 1. ファイルが属するモジュールルートを探す
  -- (UCMはUNL.finderを使って自力で探せるのでUEPに依存しなくて良い)
  local module_info = unl_finder.module.find_module(file_path)
  
  local relative_path = nil
  
  if module_info then
    local module_root = module_info.root
    -- Public / Classes / Private フォルダからの相対パスを計算
    local search_dirs = { "Public", "Classes", "Private" }
    
    for _, dir in ipairs(search_dirs) do
      local base = fs.joinpath(module_root, dir)
      -- 前方一致チェック (パス区切り文字を考慮)
      if file_path:find(base, 1, true) then
         -- base の長さ + セパレータ(1) ぶん進めたところから取得
         relative_path = file_path:sub(#base + 2)
         break
      end
    end
  end

  -- モジュール構造外、または解決できなかった場合はファイル名のみ
  if not relative_path then
    relative_path = vim.fn.fnamemodify(file_path, ":t")
  end

  local include_str = string.format('#include "%s"', relative_path)
  copy_to_clipboard(include_str)
end

function M.run(opts)
  opts = opts or {}
  local logger = log.get()

  -- 1. 直接ファイルパス指定 (API利用)
  if opts.file_path then
    resolve_and_copy(opts.file_path)
    return
  end

  -- 2. Pickerモード (Bangがある場合)
  if opts.has_bang then
    logger.debug("Requesting class list from UEP for copy_include...")
    
    -- UEPにクラス一覧を問い合わせる (Provider経由)
    local req_ok, header_details = unl_api.provider.request("uep.get_project_classes", { 
        scope = "Full", 
        logger_name = "UCM" 
    })
    
    if not req_ok or not header_details then
      return logger.error("Failed to get class list from UEP. Ensure UEP is installed and refreshed.")
    end

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

    unl_picker.pick({
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

  -- 3. カレントバッファモード
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file and current_file ~= "" then
    resolve_and_copy(current_file)
  else
    logger.warn("No file in current buffer.")
  end
end

return M
