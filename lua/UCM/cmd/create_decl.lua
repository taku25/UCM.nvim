-- lua/UCM/cmd/create_decl.lua
-- ソースファイル(.cpp)内の実装から、ヘッダーファイル(.h)に宣言を作成する

local ucm_log = require("UCM.logger")
local cmd_core = require("UCM.cmd.core")
local unl_parser = require("UNL.parser.cpp")

local M = {}

-- Treesitter node at cursor (Copied from create_impl, minimal version)
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

-- 関数定義ノードから情報を抽出する
local function parse_definition(node, bufnr)
    -- node expectation: function_definition
    
    local declarator_node = nil
    local type_node = nil
    
    -- 子ノードから検索
    for child in node:iter_children() do
        local ctype = child:type()
        if ctype == "function_declarator" then declarator_node = child end
        -- 戻り値の型 (primitive_type, type_identifier, etc)
        -- 通常は declarator の前にある
        if not declarator_node and ctype ~= "function_declarator" then
            type_node = child -- 簡易: declaratorが見つかるまでの最後のノードをtypeと仮定
        end
    end
    
    if not declarator_node then return nil, "Could not find function declarator." end

    -- declaratorの中身を解析 (qualified_identifier があるはず: Class::Func)
    local qualified_id = nil
    for child in declarator_node:iter_children() do
        if child:type() == "qualified_identifier" then
            qualified_id = child
            break
        end
    end
    
    local class_name = nil
    local func_name = nil
    
    if qualified_id then
        local scope = nil
        local name = nil

        if qualified_id.child_by_field_name then
            scope = qualified_id:child_by_field_name("scope")
            name = qualified_id:child_by_field_name("name")
        else
            -- Fallback: iterate (slower but safer)
             for child in qualified_id:iter_children() do
                 local ctype = child:type()
                 -- The structure is typically (scope) (name)
                 -- but TS for cpp might name them differently or order them consistently
                 -- Usually scope is type_identifier/namespace_identifier, name is identifier
                 -- Let's rely on child order if we can't get field names easily? No, let's try types.
                 if not scope and (ctype:match("identifier") or ctype:match("type")) then
                     scope = child
                 elseif scope and not name and (ctype:match("identifier") or ctype:match("operator")) then
                     name = child
                 end
             end
             -- Retry with field names if possible via query if above fails? 
             -- Let's assume 1st id is scope, 2nd is name for qualified_id
        end
        
        if scope then class_name = vim.treesitter.get_node_text(scope, bufnr) end
        if name then func_name = vim.treesitter.get_node_text(name, bufnr) end
    else
        -- Class::Func 形式でないなら、普通の関数か、using namespace されているメンバ
        -- ヘッダーに書く場合、クラスメソッドなら Class:: が必須のはずなので、ここでは対象外にするか警告
        -- ただしコンストラクタなどは qualified_identifier にならないケースもあるかも？
        return nil, "Function does not appear to be a class method (missing Class::Scope)."
    end

    if not class_name or not func_name then return nil, "Failed to extract Class/Function name." end
    
    -- 引数リスト
    local params_node = nil
    if declarator_node.child_by_field_name then
        params_node = declarator_node:child_by_field_name("parameters")
    else
        for child in declarator_node:iter_children() do
            if child:type() == "parameter_list" then
                params_node = child
                break
            end
        end
    end

    local params_text = params_node and vim.treesitter.get_node_text(params_node, bufnr) or "()"
    
    -- 戻り値
    local return_type = ""
    if type_node then
        -- definition全体から、declaratorの前までを取得するという手もある
        -- ここでは簡易的に type_node のテキストを取得
        -- しかし const とか inline とか virtual とかが混ざると厄介
        
        -- テキストベースで抽出: 行頭から Class::Func の手前まで
        local def_text = vim.treesitter.get_node_text(node, bufnr)
        local func_full_name = class_name .. "::" .. func_name
        local pre_part = def_text:match("^(.-)%s*" .. vim.pesc(func_full_name))
        if pre_part then
            return_type = pre_part:gsub("[\n\r]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        end
    end
    
    -- コンストラクタ/デストラクタ
    local is_ctor_dtor = (func_name == class_name or func_name == "~" .. class_name)
    if is_ctor_dtor then return_type = "" end

    return {
        class_name = class_name,
        func_name = func_name,
        return_type = return_type,
        params = params_text,
        start_row = node:range(), -- 0-indexed line number
    }
end

-- 同じファイルの前の関数を探す（アンカー用）
local function find_previous_function_name(current_row, bufnr)
    -- current_row より前にある function_definition を探す
    -- 簡易的に、Treesitterクエリで全関数を取得して、current_rowの直前のものを探す
    local query_str = [[ (function_definition declarator: (function_declarator declarator: (qualified_identifier name: (identifier) @fname))) @def ]]
    local query = vim.treesitter.query.parse("cpp", query_str)
    local parsers = require("nvim-treesitter.parsers") -- TODO: remove dependency if possible or pcall
    local parser = parsers.get_parser(bufnr, "cpp")
    local tree = parser:parse()[1]
    
    local best_func = nil
    
    for id, node, metadata in query:iter_captures(tree:root(), bufnr, 0, current_row) do
        local range = {node:range()} -- start_row, start_col, end_row, end_col
        local row = range[1]
        
        if row < current_row then
             -- 直前のものを記録更新していく
             local name_node = nil
             -- @fname captureを探すのはiter_capturesだとIDで判断が必要だが、
             -- ここでは簡易的にnodeから再検索するか、idチェックする
             -- capture id 1 is fname (in logical order of query compilation, likely)
             -- query.captures[id] tells the name
             
             if query.captures[id] == "fname" then
                 local name = vim.treesitter.get_node_text(node, bufnr)
                 -- クラス名も必要？ ヘッダー側で探すときは関数名だけで曖昧さがなければOKだが
                 -- オーバーロードがあると辛い。
                 -- 一旦関数名だけ返す
                 best_func = name
             end
        end
    end
    return best_func
end
-- 上記は複雑なので、もっと単純に:
-- Text based search backward? No, fragile.
-- Let's stick to parsing the header list via UNL.parser.cpp and matching order.

function M.execute()
  local logger = ucm_log.get()
  local current_file = vim.api.nvim_buf_get_name(0)
  
  -- 1. Must be in a cpp file
  if not (current_file:match("%.cpp$") or current_file:match("%.c$") or current_file:match("%.cc$")) then
      logger.warn("Create Declaration only works in source files.")
      return
  end

  -- 2. ペアとなるヘッダーを探す
  local pair, err = cmd_core.resolve_class_pair(current_file)
  if not pair or not pair.h then
      logger.warn("Could not find corresponding header (.h) file.")
      return
  end
  local header_file = pair.h

  -- 3. カーソル位置の関数定義を解析
  local node = get_node_at_cursor()
  while node do
      if node:type() == "function_definition" then break end
      node = node:parent()
  end
  
  if not node then
      logger.warn("Cursor is not inside a function definition.")
      return
  end

  local info, parse_err = parse_definition(node, 0)
  if not info then
      logger.error(parse_err)
      return
  end

  logger.info("Extracting: %s::%s", info.class_name, info.func_name)
  
  -- 4. ヘッダー内での挿入位置を決定
  -- UNLパーサーを使ってヘッダーのクラス情報を取得
  local h_parse = unl_parser.parse(header_file, "UCM")
  local class_data = unl_parser.find_best_match_class(h_parse, info.class_name)
  
  if not class_data then
      logger.error("Class declaration for '%s' not found in %s.", info.class_name, header_file)
      return
  end

  -- アンカー探索:
  -- 実装側で「自分よりひとつ前にある関数」を見つけ、ヘッダー内のその関数の後ろに追加する
  -- TODO: 正確な「前の関数」を見つけるロジックは実装コストが高いので、
  -- ここでは簡易版として「ヘッダーのクラス定義の末尾（publicセクションがあればそこ、なければ一番下）」に追加する。
  -- ユーザーからの要望「Riderのように」に応えるならアンカー探索が必要だが、まずは動くものを作る。
  
  -- 改善案: ヘッダー内のメソッドリストを見て、挿入位置を決める
  -- デフォルト: publicの最後
  local methods = class_data.methods.public
  local insert_line = class_data.end_line - 1 -- クラス終了の "};" の前
  
  -- もしpublicメソッドがあれば、その最後のものの後ろ
  if methods and #methods > 0 then
      insert_line = methods[#methods].line
  end

  -- 宣言コード生成
  local decl_code = ""
  if info.return_type ~= "" then
      decl_code = string.format("\t%s %s%s;", info.return_type, info.func_name, info.params)
  else
      decl_code = string.format("\t%s%s;", info.func_name, info.params)
  end

  -- 5. ヘッダーに書き込み
  -- safe_open ではなく直接編集
  local target_buf = vim.fn.bufnr(header_file)
  local is_loaded = target_buf ~= -1 and vim.api.nvim_buf_is_loaded(target_buf)
  
  if not is_loaded then
      target_buf = vim.fn.bufadd(header_file)
      vim.fn.bufload(target_buf) 
  end
  
  vim.api.nvim_buf_set_lines(target_buf, insert_line, insert_line, false, { decl_code })
  
  -- 6. ヘッダーを開いて移動
  vim.cmd("edit " .. vim.fn.fnameescape(header_file))
  vim.api.nvim_win_set_cursor(0, { insert_line + 1, 0 })
  vim.cmd("normal! zz")
  
  logger.info("Declaration created in %s", vim.fn.fnamemodify(header_file, ":t"))
end

return M
