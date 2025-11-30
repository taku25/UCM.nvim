local M = {}
local specifiers_data = require("UCM.data.specifiers").data
local unl_picker = require("UNL.backend.picker")
local log = require("UCM.logger")
local ucm_config = require("UNL.config").get("UCM")

---
-- カーソル位置から最も近い（後ろにある）マクロを検出する
-- @return string|nil マクロ名 (UPROPERTY, UFUNCTIONなど)
local function detect_macro_context()
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  local start_row = math.max(0, cursor_row - 20) -- 最大20行前まで検索
  local lines = vim.api.nvim_buf_get_lines(0, start_row, cursor_row, false)

  -- 下から上へ検索
  for i = #lines, 1, -1 do
    local line = lines[i]
    -- マクロパターンにマッチするか確認
    local macro = line:match("(U%w+)%s*%(")
    if macro and specifiers_data[macro] then
      return macro
    end
  end
  return nil
end

---
-- スペシファイアを挿入する
-- @param selections table|string 選択されたスペシファイアのリストまたは単一文字列
local function insert_specifiers(selections)
  if not selections then return end
  
  local items_to_insert = {}
  
  if type(selections) == "table" then
    -- マルチセレクトの場合、テーブルが返ってくることを想定
    for _, item in ipairs(selections) do
        -- UNL pickerがオブジェクトを返す場合と文字列を返す場合を考慮
        local val = type(item) == "table" and (item.value or item.label) or item
        table.insert(items_to_insert, val)
    end
  elseif type(selections) == "string" then
    table.insert(items_to_insert, selections)
  end

  if #items_to_insert == 0 then return end

  local insert_text = table.concat(items_to_insert, ", ")
  
  -- カーソル位置に挿入
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  
  -- カーソルが括弧内にあるか簡易チェックし、必要ならカンマを前置するなどの微調整が可能だが
  -- ここでは単純挿入とする (ユーザーがカンマ位置を調整するほうが安全)
  local new_line = line:sub(1, col + 1) .. insert_text .. line:sub(col + 2)
  vim.api.nvim_set_current_line(new_line)
  
  -- カーソルを挿入したテキストの後ろへ移動
  vim.api.nvim_win_set_cursor(0, { row, col + #insert_text })
end

function M.run(opts)
  opts = opts or {}
  local logger = log.get()

  -- 1. コンテキスト検出
  local macro_type = detect_macro_context()
  
  -- 検出できない場合は、マクロタイプを選択させる
  if not macro_type or opts.force_select then
    local macros = vim.tbl_keys(specifiers_data)
    table.sort(macros)
    
    local picker_items = {}
    for _, m in ipairs(macros) do
        table.insert(picker_items, { label = m, value = m })
    end

    unl_picker.pick({
      title = "Select Macro Type",
      items = picker_items,
      conf = ucm_config,
      preview_enabled = false, -- ★修正: プレビューを無効化
      on_submit = function(selected)
        if selected then
            local m_type = type(selected) == "table" and selected.value or selected
            M.show_specifier_picker(m_type)
        end
      end
    })
    return
  end

  M.show_specifier_picker(macro_type)
end

function M.show_specifier_picker(macro_type)
  local items_data = specifiers_data[macro_type]
  if not items_data then return end

  local picker_items = {}
  for _, item in ipairs(items_data) do
    table.insert(picker_items, {
      label = item.label,
      value = item.label,
      desc = item.desc, -- プレビューや説明用
      display = string.format("%-35s %s", item.label, item.desc and ("# " .. item.desc) or "")
    })
  end

  unl_picker.pick({
    kind = "ucm_specifiers",
    title = "Select Specifiers for " .. macro_type,
    items = picker_items,
    conf = ucm_config,
    multi_select = true, 
    
    -- ★修正: プレビューを無効化 (これがエラーの主因)
    preview_enabled = false, 
    
    -- telescopeなどで説明を表示するためのフォーマット関数（オプション）
    format = function(item)
        return item.display
    end,

    on_submit = function(selection)
      insert_specifiers(selection)
    end
  })
end

return M
