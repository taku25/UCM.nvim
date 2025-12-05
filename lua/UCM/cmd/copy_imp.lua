-- lua/UCM/cmd/copy_imp.lua
local ucm_log = require("UCM.logger")

local M = {}

-- ノードからテキストを取得
local function get_text(node, bufnr)
  return vim.treesitter.get_node_text(node, bufnr)
end

-- パラメータテキストをクリーニングする (テキストベース処理)
-- "float Scale = 1.0f" -> "float Scale"
-- "const FVector& \n Dir = FVector::UpVector" -> "const FVector& Dir"
local function clean_parameter_text(param_node, bufnr)
  local text = get_text(param_node, bufnr)
  
  -- 1. コメントを除去 (簡易的)
  text = text:gsub("/%*.-%*/", ""):gsub("//.-[\r\n]", "")
  
  -- 2. デフォルト引数 (= 以降) を削除
  -- Tree-sitterのパラメータノードはカンマを含まないので、=以降を全部消してOK
  text = text:gsub("%s*=.*", "")
  
  -- 3. 改行や連続スペースを1つのスペースに正規化
  text = text:gsub("%s+", " ")
  
  -- 4. 前後の空白除去
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- パラメータノードから変数名「だけ」を抽出する (Super呼び出し用)
local function extract_arg_name(param_node, bufnr)
  -- 1. Tree構造から identifier を探す
  local function find_identifier_recursive(node)
    local count = node:child_count()
    for i = 0, count - 1 do
      local child = node:child(i)
      local type = child:type()
      
      -- デフォルト値の定義に入ったら探索しない
      if type == "default_value" or get_text(child, bufnr) == "=" then
          return nil
      end
      
      if type == "array_declarator" then
          return find_identifier_recursive(child)
      end
      
      if type == "identifier" or type == "field_identifier" then
        return get_text(child, bufnr)
      end
      
      -- ポインタや参照 (*, &) の中を潜る
      if type == "pointer_declarator" or type == "reference_declarator" or type == "type_qualifier" then
         local res = find_identifier_recursive(child)
         if res then return res end
      end
    end
    return nil
  end

  local name = find_identifier_recursive(param_node)
  
  -- 2. 見つからない場合のフォールバック (クリーニング済みテキストの末尾)
  if not name then
      local clean_text = clean_parameter_text(param_node, bufnr)
      -- 配列 "[3]" などを除去してから末尾を取得
      local text_no_brackets = clean_text:gsub("%[.*%]", "")
      name = text_no_brackets:match("([%w_]+)%s*$")
  end
  
  return name or ""
end

-- 関数宣言部分 (function_declarator) を探す
local function find_func_declarator(cursor_node)
  local node = cursor_node
  while node do
    if node:type() == "function_declarator" then
      return node
    end
    node = node:parent()
  end
  return nil
end

-- クラス定義を探す
local function find_class_node(node)
  local current = node
  while current do
    local t = current:type()
    if t == "class_specifier" or t == "struct_specifier" 
       or t == "unreal_class_declaration" or t == "unreal_struct_declaration" then
      return current
    end
    current = current:parent()
  end
  return nil
end

-- 修飾子 (const, override) を探す
local function check_modifiers(func_declarator, bufnr)
    local is_const = false
    local is_override = false
    
    -- ヘルパー: テキストチェック
    local function analyze_text(txt)
        if txt == "const" then is_const = true end
        if txt == "override" then is_override = true end
    end

    -- 1. declarator の中身をチェック (末尾の const など)
    for child in func_declarator:iter_children() do
        analyze_text(get_text(child, bufnr))
    end

    -- 2. 親ノード (field_declaration / unreal_function_declaration) の子要素をチェック
    local parent = func_declarator:parent()
    if parent then
        for child in parent:iter_children() do
            local txt = get_text(child, bufnr)
            analyze_text(txt)
            
            -- virtual_specifier ノードの中身も念のため見る
            if child:type() == "virtual_specifier" then
               if txt:match("override") then is_override = true end
            end
        end
    end
    
    return is_const, is_override
end

function M.execute()
  local log = ucm_log.get()
  local bufnr = vim.api.nvim_get_current_buf()
  
  local cursor_node = vim.treesitter.get_node()
  if not cursor_node then return log.warn("TS node not found.") end

  local func_declarator = find_func_declarator(cursor_node)
  if not func_declarator then return log.warn("Cursor not in function declarator.") end

  local class_node = find_class_node(func_declarator)
  if not class_node then return log.warn("Parent class not found.") end

  -- クラス名
  local class_name = ""
  for child in class_node:iter_children() do
    if child:type():match("identifier") or child:type() == "name" then
       class_name = get_text(child, bufnr)
       break
    end
  end

  -- 関数名、引数、Super用引数
  local func_name = ""
  local params_text = ""
  local arg_names = {}
  
  for child in func_declarator:iter_children() do
      local t = child:type()
      if t == "field_identifier" or t == "identifier" then
          func_name = get_text(child, bufnr)
      elseif t == "parameter_list" then
          local params = {}
          for param in child:iter_children() do
              local pt = param:type()
              -- parameter_declaration または optional_parameter_declaration を対象
              if pt == "parameter_declaration" or pt == "optional_parameter_declaration" then
                  -- シグネチャ用: テキストベースで強力にクリーニング
                  local p_text = clean_parameter_text(param, bufnr)
                  table.insert(params, p_text)
                  
                  -- Super呼び出し用: 変数名抽出
                  local arg_name = extract_arg_name(param, bufnr)
                  if arg_name and arg_name ~= "" then
                      table.insert(arg_names, arg_name)
                  end
              end
          end
          params_text = "(" .. table.concat(params, ", ") .. ")"
      end
  end

  if func_name == "" then return log.warn("Function name not found.") end

  -- 戻り値の型
  local return_type = "void"
  local prev = func_declarator:prev_sibling()
  while prev do
      local t = prev:type()
      local txt = get_text(prev, bufnr)
      if txt ~= "virtual" and txt ~= "static" and txt ~= "inline" and txt ~= "explicit" 
         and not t:match("macro") and not t:match("comment") then
          return_type = txt
          break
      end
      prev = prev:prev_sibling()
  end

  -- 修飾子判定
  local is_const, is_override = check_modifiers(func_declarator, bufnr)

  -- コード生成
  local args_str = table.concat(arg_names, ", ")
  local super_call = ""
  
  if is_override then
      if return_type ~= "void" and return_type ~= "" then
          super_call = string.format("\n\treturn Super::%s(%s);", func_name, args_str)
      else
          super_call = string.format("\n\tSuper::%s(%s);", func_name, args_str)
      end
  end

  local code = string.format("%s %s::%s%s%s\n{%s\n}", 
      return_type, 
      class_name, 
      func_name, 
      params_text,
      is_const and " const" or "",
      super_call
  )

  vim.fn.setreg('+', code)
  vim.fn.setreg('"', code)

  log.info("Copied: %s::%s", class_name, func_name)
  vim.notify("Copied implementation!", vim.log.levels.INFO)
end

return M
