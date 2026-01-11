-- lua/UCM/cmd/create_impl.lua
-- ヘッダーファイル(.h)内の宣言から、ソースファイル(.cpp)に実装を作成する

local ucm_log = require("UCM.logger")
local cmd_core = require("UCM.cmd.core")

local M = {}

-- Treesitter node at cursor (Core implementation)
local function get_node_at_cursor()
    local bufnr = vim.api.nvim_get_current_buf()
    local winnr = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(winnr)
    local row, col = cursor[1] - 1, cursor[2]

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if not ok or not parser then return nil end

    local tree = parser:parse()[1]
    if not tree then return nil end
    local root = tree:root()

    return root:named_descendant_for_range(row, col, row, col)
end


-- 引数リスト文字列から、引数名のみを抽出する (Super呼び出し用)
-- 例: "(const FString& Name, int32 Count = 0)" -> "Name, Count"
local function extract_arg_names(params_str)
    if not params_str or params_str == "()" or params_str == "" then return "" end
    local content = params_str:match("^%s*%(?(.-)%)?%s*$")
    if not content or content == "" then return "" end
    
    local args = {}
    -- 簡易パーサー: カンマで分割 (テンプレート内のカンマなどは考慮していない簡易版)
    -- TODO: テンプレート型(TMap<A,B>)などに対応するにはスタックベースの解析が必要
    for param in content:gmatch("[^,]+") do
        -- デフォルト引数除去
        local param_no_default = param:gsub("=.*$", "")
        -- 末尾の単語(変数名)を取得
        -- "const FString& Name" -> "Name"
        -- "float* Value" -> "Value"
        -- "int A[]" -> "A" (本当は A[] だが呼び出しでは A)
        local name = param_no_default:gsub("%[.*%]", ""):match("([%w_]+)%s*$")
        if name then table.insert(args, name) end
    end
    return table.concat(args, ", ")
end

-- 関数宣言ノードから情報を抽出する
local function parse_declaration(node, bufnr)
    local text = vim.treesitter.get_node_text(node, bufnr)
    
    -- 1. クラス名 (親を辿る)
    local parent = node:parent()
    local class_name = nil
    while parent do
        local type = parent:type()
        if type == "class_specifier" or type == "struct_specifier" or 
           type == "unreal_class_declaration" or type == "unreal_struct_declaration" then
            -- Note: Some TS parsers/versions might not implement child_by_field_name correctly or node might be userdata.
            -- Using a safer checking method or iterating.
            local name_node = nil
            if parent.child_by_field_name then
                name_node = parent:child_by_field_name("name")
            else
                 -- Fallback: iterate (slower but safer)
                 for child in parent:iter_children() do
                     if child:type() == "type_identifier" or child:type() == "identifier" then -- Assuming name is an identifier
                         name_node = child
                         break -- naive assumption, usually name is the first identifier
                     end
                 end
            end
            
            if name_node then
                class_name = vim.treesitter.get_node_text(name_node, bufnr)
            end
            break
        end
        parent = parent:parent()
    end
    
    if not class_name then return nil, "Could not determine class name." end

    -- 2. 関数名と引数
    -- nodeは field_declaration か function_definition を想定
    --  field_declaration -> type + declarator(function_declarator)
    local func_declarator = nil
    for child in node:iter_children() do
        if child:type() == "function_declarator" then
            func_declarator = child
            break
        end
    end
    
    if not func_declarator then
        -- 既に関数宣言そのものかもしれない
        if node:type() == "function_declarator" then
            func_declarator = node
        else
            -- ポインタや参照の場合の探索
            -- type: pointer_declarator -> function_declarator
             local queries = vim.treesitter.query.parse("cpp", [[
                (function_declarator) @fd
            ]])
            for _, capture in queries:iter_captures(node, bufnr, 0, -1) do
                func_declarator = capture
                break
            end
        end
    end

    if not func_declarator then return nil, "Could not find function structure." end

    local func_name_node = nil 
    local parameters_node = nil
    
    if func_declarator.child_by_field_name then
        func_name_node = func_declarator:child_by_field_name("declarator")
        parameters_node = func_declarator:child_by_field_name("parameters")
    else
        -- Fallback if method missing
        for child in func_declarator:iter_children() do
             local ctype = child:type()
             if ctype == "field_identifier" or ctype == "identifier" then func_name_node = child end
             if ctype == "parameter_list" then parameters_node = child end
        end
    end
    
    local func_name = func_name_node and vim.treesitter.get_node_text(func_name_node, bufnr) or "UnknownResult"
    -- 修飾子付き名前(MyClass::Func)だった場合の処理
    if func_name:match("::") then
         func_name = func_name:match("::([%w_]+)$")
    end

    local params_text = parameters_node and vim.treesitter.get_node_text(parameters_node, bufnr) or "()"
    
    -- 3. 戻り値
    -- field_declaration の type フィールド、またはテキスト解析
    -- "virtual void Func()" -> "void"
    -- "static int32 Func()" -> "int32"
    local raw_text = vim.treesitter.get_node_text(node, bufnr)
    
    -- 簡易解析: 関数名の前の部分を戻り値候補とする
    -- virtual, static, explicit, friend は除去
    local pre_name_part = raw_text:match("^(.*)" .. vim.pesc(func_name))
    if not pre_name_part then pre_name_part = "void " end
    
    pre_name_part = pre_name_part:gsub("virtual%s+", "")
    pre_name_part = pre_name_part:gsub("static%s+", "")
    pre_name_part = pre_name_part:gsub("explicit%s+", "")
    pre_name_part = pre_name_part:gsub("friend%s+", "")
    pre_name_part = pre_name_part:gsub("inline%s+", "")
    pre_name_part = pre_name_part:gsub("%s+$", "") -- 末尾スペース削除
    
    local return_type = pre_name_part
    if return_type == "" then return_type = "void" end -- コンストラクタ/デストラクタの場合は実際は空文字が良いがとりあえず

    -- コンストラクタ/デストラクタ判定
    local is_ctor_dtor = (func_name == class_name or func_name == "~" .. class_name)
    if is_ctor_dtor then return_type = "" end
    
    local is_override = raw_text:match("override") ~= nil
    
    -- パラメータからデフォルト引数を除去
    -- "(int A, int B = 10)" -> "(int A, int B)"
    local clean_params = params_text:gsub("%s*=%s*[^,%)%s]+", ""):gsub("%s*=%s*[^,%)%s]*%b()", "") -- 簡易的なデフォルト値除去

    return {
        class_name = class_name,
        func_name = func_name,
        return_type = return_type,
        params = clean_params,
        orig_params = params_text,
        is_override = is_override,
        is_ctor_dtor = is_ctor_dtor
    }
end

function M.execute()
  local logger = ucm_log.get()
  
  local current_file = vim.api.nvim_buf_get_name(0)
  
  -- 1. ヘッダーファイルチェック
  if not (current_file:match("%.h$") or current_file:match("%.hpp$")) then
      logger.warn("Create Implementation only works in header files.")
      return
  end
  
  -- 2. ペアとなるCPPファイルを探す
  local pair, err = cmd_core.resolve_class_pair(current_file)
  if not pair or not pair.cpp then
      logger.warn("Could not find corresponding source (.cpp) file.")
      return
  end
  local cpp_file = pair.cpp

  -- 3. カーソル下の関数宣言を取得
  local node = get_node_at_cursor()
  while node do
      if node:type() == "function_definition" or node:type() == "field_declaration" or node:type() == "declaration" then
          break
      end
      node = node:parent()
  end
  
  if not node then
      logger.warn("Could not find a function declaration at cursor.")
      return
  end

  local info, parse_err = parse_declaration(node, 0)
  if not info then
      logger.error(parse_err)
      return
  end
  
  logger.info("Generating implementation for %s::%s...", info.class_name, info.func_name)
  
  -- 4. 実装コード生成
  local prefix = (info.return_type ~= "") and (info.return_type .. " ") or ""
  local signature = string.format("%s%s::%s%s", prefix, info.class_name, info.func_name, info.params)
  
  local body = ""
  if info.is_override then
      local args = extract_arg_names(info.orig_params)
      if info.return_type == "void" or info.return_type == "" then
          body = string.format("    Super::%s(%s);\n", info.func_name, args)
      else
          body = string.format("    return Super::%s(%s);\n", info.func_name, args)
      end
  end
  
  local impl_code = string.format("\n%s\n{\n%s}\n", signature, body)
  local lines_to_append = vim.split(impl_code, "\n")

  -- 5. CPPファイルに追記
  -- バッファが既に開かれているか確認
  local target_buf = vim.fn.bufnr(cpp_file)
  local is_loaded = target_buf ~= -1 and vim.api.nvim_buf_is_loaded(target_buf)
  
  if is_loaded then
      -- バッファに追記
      local line_count = vim.api.nvim_buf_line_count(target_buf)
      vim.api.nvim_buf_set_lines(target_buf, line_count, line_count, false, lines_to_append)
      vim.cmd("edit " .. vim.fn.fnameescape(cpp_file)) -- アクティブにする
  else
      -- ファイルを読み込んで追記して保存
      local cpp_lines = vim.fn.readfile(cpp_file)
      for _, l in ipairs(lines_to_append) do
          table.insert(cpp_lines, l)
      end
      vim.fn.writefile(cpp_lines, cpp_file)
      vim.cmd("edit " .. vim.fn.fnameescape(cpp_file))
  end
  
  -- 6. カーソル移動
  vim.cmd("$") -- 末尾へ移動
  vim.cmd("normal! zz") -- 中央へ
  
  logger.info("Implementation created in %s", vim.fn.fnamemodify(cpp_file, ":t"))
end

return M
