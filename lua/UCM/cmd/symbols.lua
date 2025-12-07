local unl_picker = require("UNL.backend.picker")
local unl_api = require("UNL.api")
local unl_buf_open = require("UNL.buf.open")
local ucm_config = require("UNL.config").get("UCM")
local log = require("UCM.logger")

local M = {}

-- ★追加: 階層構造をフラットなリストに変換する関数
local function flatten_hierarchy(symbols)
  local flat_list = {}
  
  for _, item in ipairs(symbols) do
    -- 1. クラス/構造体自体もリストに追加
    table.insert(flat_list, item)

    -- 2. クラス/構造体なら、その中身（メソッド・プロパティ）を取り出して追加
    if item.kind == "UClass" or item.kind == "Class" or 
       item.kind == "UStruct" or item.kind == "Struct" then
       
       -- Methods (関数)
       if item.methods then
         for _, access in ipairs({"public", "protected", "private", "impl"}) do
           if item.methods[access] then
             for _, method in ipairs(item.methods[access]) do
               -- 親クラス名などの情報を付与しておくと表示時に便利（今回はシンプルに追加）
               table.insert(flat_list, method)
             end
           end
         end
       end

       -- Fields (変数/プロパティ)
       if item.fields then
         for _, access in ipairs({"public", "protected", "private", "impl"}) do
           if item.fields[access] then
             for _, field in ipairs(item.fields[access]) do
               table.insert(flat_list, field)
             end
           end
         end
       end
    end
  end
  
  return flat_list
end

-- シンボルリストをピッカーで表示する
local function show_picker(file_path, symbols)
  -- ★修正: ここでフラット化を実行
  local flat_symbols = flatten_hierarchy(symbols)
  local items = {}
  
  for _, item in ipairs(flat_symbols) do
    local kind = item.kind or "Unknown"
    local kind_lower = kind:lower()
    
    local icon = " "
    local hl_group = "Function" 

    if kind_lower:find("function") then 
        icon = "󰊕 "
        hl_group = "Function"
    elseif kind_lower:find("property") or kind_lower:find("field") then 
        icon = " " 
        hl_group = "Identifier"
    elseif kind_lower:find("class") or kind_lower:find("struct") then 
        icon = "󰌗 " 
        hl_group = "Type"
    elseif kind_lower:find("enum") then 
        icon = "En " 
        hl_group = "Type"
    end

    table.insert(items, {
      display = string.format("%s %-35s  (%s)", icon, item.name, kind),
      value = item,
      filename = item.file_path,
      lnum = item.line,
      kind = kind,
      -- アイコン部分の色付けなどが可能なピッカー用に情報を残す
      icon = icon,
    })
  end

  if #items == 0 then
    return vim.notify("No symbols found in " .. vim.fn.fnamemodify(file_path, ":t"), vim.log.levels.WARN)
  end

  unl_picker.pick({
    kind = "ucm_symbols",
    title = "Symbols in " .. vim.fn.fnamemodify(file_path, ":t"),
    items = items,
    conf = ucm_config,
    preview_enabled = true,
    
    -- telescopeなどで表示順を維持させるためのオプション（もしあれば）
    sorter_opts = { preserve_order = true },

    on_submit = function(selection)
      if selection and selection.value then
        -- 該当行へジャンプ
        unl_buf_open.safe({ 
            file_path = selection.filename, 
            open_cmd = "edit", 
            plugin_name = "UCM" 
        })
        vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
        vim.cmd("normal! zz")
      end
    end
  })
end

---
-- メイン実行関数
-- @param opts table { file_path = "..." (optional) }
function M.execute(opts)
  opts = opts or {}
  local target_file = opts.file_path or vim.api.nvim_buf_get_name(0)
  
  if target_file == "" then
    return log.get().warn("No file to parse.")
  end

  log.get().debug("Parsing symbols for: %s", target_file)

  -- プロバイダー経由で解析結果を取得
  local ok, symbols = unl_api.provider.request("ucm.get_file_symbols", {
      file_path = target_file
  })

  if ok and symbols then
      show_picker(target_file, symbols)
  else
      log.get().error("Failed to parse symbols for %s", target_file)
  end
end

return M
