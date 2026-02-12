local M = {}
local specifiers_data = require("UCM.data.specifiers").data
local unl_picker = require("UNL.picker")
local log = require("UCM.logger")
local ucm_config = require("UNL.config").get("UCM")

---
-- テキストをクリップボードにコピーする
local function copy_to_clipboard(text)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
end

---
-- テキストを生成して挿入し、カーソル位置を調整する
-- @param macro_type string マクロ名 (UPROPERTY, UFUNCTION 等)
-- @param selections table|string 選択されたスペシファイア
-- @param is_append_mode boolean trueなら中身だけ、falseならマクロ枠付き
local function generate_and_insert(macro_type, selections, is_append_mode)
  local specifiers_list = {}
  
  if selections then
    if type(selections) == "table" then
      for _, item in ipairs(selections) do
          local val = type(item) == "table" and (item.value or item.label) or item
          table.insert(specifiers_list, val)
      end
    elseif type(selections) == "string" and selections ~= "" then
      table.insert(specifiers_list, selections)
    end
  end

  -- リストをカンマ区切りにする
  local args_str = table.concat(specifiers_list, ", ")
  
  -- モードによるテキスト生成の分岐
  local final_text = ""
  if is_append_mode then
      -- 追記モード (!): 中身だけ (例: "EditAnywhere, BlueprintReadWrite")
      final_text = args_str
  else
      -- 通常モード: マクロ枠付き (例: "UPROPERTY(EditAnywhere, BlueprintReadWrite)")
      final_text = string.format("%s(%s)", macro_type, args_str)
  end

  -- 何も生成されなかった場合（追記モードで選択なし）は終了
  if final_text == "" then return end

  -- 1. クリップボードにコピー
  copy_to_clipboard(final_text)

  -- 2. バッファに挿入
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  
  -- 挿入開始位置(カラム)を計算
  local insertion_start_col = col

  if line:match("^%s*$") then
      -- 行が空ならインデント維持して置き換え
      local indent = line:match("^(%s*)") or ""
      insertion_start_col = #indent
      vim.api.nvim_set_current_line(indent .. final_text)
  else
      -- カーソル位置に挿入
      local new_line = line:sub(1, col + 1) .. final_text .. line:sub(col + 2)
      vim.api.nvim_set_current_line(new_line)
  end
  
  -- 3. カーソル位置の調整 (Smart Cursor)
  -- 生成された文字列の中に `""` があるか探す
  local quote_start = final_text:find('""')
  
  if quote_start then
      -- `""` があれば、その間にカーソル移動
      vim.api.nvim_win_set_cursor(0, { row, insertion_start_col + quote_start })
  else
      -- なければ末尾に移動
      vim.api.nvim_win_set_cursor(0, { row, insertion_start_col + #final_text })
  end
  
  vim.notify(string.format("Inserted: %s", final_text), vim.log.levels.INFO)
end

-- Step 2: スペシファイアを選択するピッカーを表示
function M.show_specifier_picker(macro_type, is_append_mode)
  local items_data = specifiers_data[macro_type]
  if not items_data then 
      generate_and_insert(macro_type, {}, is_append_mode)
      return 
  end

  local picker_items = {}
  for _, item in ipairs(items_data) do
    table.insert(picker_items, {
      label = item.label,
      value = item.label,
      desc = item.desc,
      display = string.format("%-35s %s", item.label, item.desc and ("# " .. item.desc) or "")
    })
  end

  unl_picker.open({
    kind = "ucm_specifiers",
    title = string.format("Select Specifiers for %s %s", macro_type, is_append_mode and "(Append)" or "(New)"),
    items = picker_items,
    conf = ucm_config,
    multi_select = true, 
    preview_enabled = false, 
    
    format = function(item)
        return item.display
    end,

    on_submit = function(selection)
      generate_and_insert(macro_type, selection or {}, is_append_mode)
    end
  })
end

-- Step 1: マクロタイプ (UPROPERTY等) を選択するピッカーを表示
function M.run(opts)
  opts = opts or {}
  
  -- ★★★ 修正箇所 ★★★
  -- copy_includeの実装に合わせて opts.has_bang を参照するように修正しました
  local is_append_mode = opts.has_bang or opts.bang or false

  local macros = vim.tbl_keys(specifiers_data)
  table.sort(macros)
  
  local picker_items = {}
  for _, m in ipairs(macros) do
      table.insert(picker_items, { label = m, value = m })
  end

  unl_picker.open({
    title = "Select Macro Type",
    items = picker_items,
    conf = ucm_config,
    preview_enabled = false,
    on_submit = function(selected)
      if selected then
          local m_type = type(selected) == "table" and selected.value or selected
          M.show_specifier_picker(m_type, is_append_mode)
      end
    end
  })
end

return M

