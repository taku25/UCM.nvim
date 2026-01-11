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


-- Helper: Flatten method lists
local function flatten_methods(class_data)
    local list = {}
    if not class_data or not class_data.methods then return list end
    for _, access in ipairs({"public", "protected", "private"}) do
        if class_data.methods[access] then
            for _, m in ipairs(class_data.methods[access]) do
                table.insert(list, m)
            end
        end
    end
    return list
end

-- Helper: Update existing declaration in header

-- Helper: List of node types that are specifiers (should be kept)
local KEEP_SPECIFIERS = {
    ["virtual"] = true,
    ["storage_class_specifier"] = true, -- static, inline, extern
    ["explicit_function_specifier"] = true, -- explicit
    ["ufunction_macro"] = true, -- UFUNCTION
    ["friend_declaration"] = true -- friend (or friend keyword)
}

local function get_return_type_range_in_header(container_node, name_node_start_col, bufnr)
    -- Iterate children of container to find the "gap" between specifiers/macros and the function name.
    -- Everything in expected return type position will be overwritten.
    -- Returns start_byte, end_byte (0-indexed, exclusive end?) - fitting buffer set_text expectations.
    
    local replace_start_row, replace_start_col = container_node:range()
    -- Default start: container start (e.g. start of indentation or line)
    
    -- BUT, container range might include indentation or previous elements?
    -- No, Treesitter ranges usually start at the first character of the node.
    -- Check if container is 'field_declaration', it usually starts at the beginning of the text on the line.
    
    local found_specifier = false
    local last_spec_end_row, last_spec_end_col = replace_start_row, replace_start_col

    for child in container_node:iter_children() do
        local c_type = child:type()
        
        -- Special case: specifiers we want to KEEP
        if KEEP_SPECIFIERS[c_type] then
            _, _, last_spec_end_row, last_spec_end_col = child:range()
            found_specifier = true
        elseif c_type == "comment" then
             -- preserve comments? If comment is before return type.
             -- Assume comments are specifiers for now to be safe.
             _, _, last_spec_end_row, last_spec_end_col = child:range()
             found_specifier = true
        else
            -- We hit something that is NOT a specifier.
            -- It could be the return type (primitive_type, type_identifier, etc.)
            -- Or it could be the function declarator itself (if void or ctor).
            
            -- If we hit the function name directly (e.g. constructor), we stop.
            -- But we are iterating children of container. 
            -- The 'function_declarator' is a child.
            -- The 'name_node' corresponds to start of function declarator (usually).
            
            -- Actually, let's use the 'name_node_start_col' acts as a hard stop.
            local c_s_row, c_s_col, _, _ = child:range()
            
            -- If this child STARTS at or after the name, we are done.
            if c_s_row > replace_start_row or c_s_col >= name_node_start_col then
                break
            end
            
            -- If it's the function_declarator itself (even if it contains name inside):
            -- We stop.
            if c_type == "function_declarator" or c_type == "pointer_declarator" or c_type == "reference_declarator" then
                -- Wait, if it is 'pointer_declarator', does it contain the '*' which is part of type?
                -- "MyType* Func" -> 'MyType' is child 1. 'pointer_declarator' is child 2.
                -- If we want to replace 'MyType*', we need to include 'pointer_declarator' START?
                -- No, 'pointer_declarator' contains the function name.
                -- So we CANNOT replace the whole pointer_declarator.
                
                -- This is tricky. 
                -- "int* Func" -> pointer_declarator(* Func).
                -- If we replace "int", we get "void* Func". 
                -- If we want "void Func", we must delete "*".
                -- But "*" is inside pointer_declarator.
                
                -- So we cannot just use child iteration on container.
                break
            end
        end
    end
    
    -- So, how to handle 'pointer_declarator'?
    -- We want to replace everything from [End of Specifiers] to [Start of Name].
    -- Name is the identifier node.
    -- This ignores the structure of declarators wrapping the name.
    
    -- If found_specifier, start from last_spec_end.
    -- If not, start from container start.
    
    return last_spec_end_row, last_spec_end_col
end

-- Update existing declaration in header
local function update_declaration_in_header(target_buf, method_info, new_info, logger)
    local line_idx = method_info.line - 1
    local line_text = vim.api.nvim_buf_get_lines(target_buf, line_idx, line_idx + 1, false)[1]
    if not line_text then return false end
    
    -- SAFETY: Check if line actually contains the function name
    if not string.find(line_text, method_info.name, 1, true) then
        logger.warn("Header line %d does not contain '%s'. Skipping update.", method_info.line, method_info.name)
        return false
    end

    local ok, parser = pcall(vim.treesitter.get_parser, target_buf, "cpp")
    if not ok then
        logger.error("Treesitter parser error for header update.")
        return false
    end
    local tree = parser:parse()[1]
    local root = tree:root()
    
    -- Calculate precise range to avoid picking parent container (like field_declaration_list) due to indentation
    local s_col = (line_text:find("%S") or 1) - 1
    local _, e_col = line_text:find(".*%S")
    if not e_col then e_col = #line_text end

    -- Find the function_declarator or field_declaration at line
    local target_node = root:named_descendant_for_range(line_idx, s_col, line_idx, e_col)
    
    -- Fallback: If we still got a list/block node (e.g. cursor was on a boundary?), drill down
    if target_node:type() == "field_declaration_list" or target_node:type() == "declaration_list" then
        for child in target_node:iter_children() do
            local cr, _, _, _ = child:range()
            if cr == line_idx then
                target_node = child
                break
            end
        end
    end

    -- Traverse up to find container (field_declaration, declaration, or UFUNCTION container)
    local container_node = nil
    local curr = target_node
    while curr do
        local t = curr:type()
        if t == "field_declaration" or t == "declaration" or t == "function_definition" or t == "unreal_function_declaration" then
            container_node = curr
            -- If generic declaration found, keep going up just in case it's wrapped in UFUNCTION
        end
        -- Keep going up until root to find the outermost container on this line
        local parent = curr:parent()
        if parent then
            local p_start_row, _, _, _ = parent:range()
            if p_start_row == line_idx then
                 curr = parent
            else
                 break
            end
        else
             break
        end
    end
    
    -- If loop finished, container_node is the highest node on this line.
    -- But we might have gone too far if multiple statements on line? 
    -- Assuming one decl per line for now.
    -- Actually, safer to stop if we hit 'unreal_function_declaration' or 'field_declaration'.
    
    if not container_node then 
        -- Check target_node type before fallback
        local t = target_node:type()
        if t == "field_declaration" or t == "function_declarator" then
             container_node = target_node
        else
             logger.error("Could not determine a valid declaration container node at line %d. (Got type: %s)", line_idx + 1, t)
             return false
        end
    end

    -- Double check: container should NOT be a list
    if container_node:type():match("list") or container_node:type():match("specifier") or container_node:type() == "translation_unit" then
         -- Exception: unreal_function_declaration is fine.
         -- But 'class_specifier' is bad. 'field_declaration_list' is bad.
         logger.error("Resolved container node is too broad (%s). Aborting to prevent data loss.", container_node:type())
         return false
    end

    -- Identify the "Name" node (identifier/field_identifier)
    -- This is our anchor for "End of Return Type".
    local name_node = nil
    local query = vim.treesitter.query.parse("cpp", [[
       (function_declarator declarator: (identifier) @name)
       (function_declarator declarator: (field_identifier) @name)
       (function_declarator declarator: (destructor_name) @name)
    ]])
    -- Note: This query matches SIMPLE identifier inside function_declarator. 
    -- Does not handle pointer/ref declarators well if they wrap it?
    -- Actually: (pointer_declarator (function_declarator...))
    -- So the INNER lookup key is the identifier.
    
    -- Just search specifically for identifier with expected name?
    -- Using tree search for identifier text match is risky if args have same name.
    
    -- Use recursive search from container
    local function find_name_node(n)
        if n:type() == "identifier" or n:type() == "field_identifier" or n:type() == "destructor_name" then
             if vim.treesitter.get_node_text(n, target_buf) == method_info.name then
                 return n
             end
        end
        for child in n:iter_children() do
            local res = find_name_node(child)
            if res then return res end
        end
        return nil
    end
    
    name_node = find_name_node(container_node)
    
    if not name_node then
        logger.error("Could not locate function name '%s' in header structure.", method_info.name)
        return false
    end

    local name_row, name_col, _, _ = name_node:range()

    ---- 1. PARAMETER UPDATE ----
    -- Find parameter_list node inside container
    local param_list_node = nil
    -- Scan strictly for parameter_list
    local function find_params(n)
        if n:type() == "parameter_list" then return n end
        for child in n:iter_children() do
            local res = find_params(child)
            if res then return res end
        end
    end
    param_list_node = find_params(container_node)

    if param_list_node then
         local s_row, s_col, e_row, e_col = param_list_node:range()
         vim.api.nvim_buf_set_text(target_buf, s_row, s_col, e_row, e_col, { new_info.params })
         -- Note: param_list_node range becomes invalid after this if line changes length?
         -- But we are doing Return Type update next.
         -- If Params change length, the columns after it shift.
         -- BUT Return Type is *before* Params. So Return Type position is stable?
         -- Wait. name_node is BEFORE Params.
         -- Return Type is BEFORE name_node. 
         -- So changing Params does NOT affect Return Type Range. Safe.
    end
    
    ---- 2. RETURN TYPE UPDATE ----
    -- Determine range [End of Specifiers] -> [Start of Name]
    local s_row, s_col, _, _ = container_node:range()
    
    -- Find start point (after specifiers)
    -- We can iterate children of container like before, BUT we need to handle "pointer_declarator" correctly.
    -- The strategy [Start of Name] handles the end point perfectly (it cuts off '*' if present before name).
    -- Wait. "int * Func". Name is "Func".
    -- Range [Start] to [Start of Func] covers "int * ".
    -- If we replace "int * " with "void ", we get "void Func". Correct.
    
    local found_specifier = false
    local replace_start_row, replace_start_col = s_row, s_col
    
    for child in container_node:iter_children() do
        -- Skip comments?
        if KEEP_SPECIFIERS[child:type()] then
            _, _, replace_start_row, replace_start_col = child:range()
            found_specifier = true
        end
        -- If we hit something that is NOT a specifier, we assume it's part of return type or declarator.
        -- We won't update replace_start anymore.
        -- Exception: comments?
        if not KEEP_SPECIFIERS[child:type()] and child:type() ~= "comment" then
             break
        end
    end
    
    -- Calculate range end = name start
    -- s_row, s_col (of name)
    local replace_end_row, replace_end_col = name_row, name_col
    
    -- Content to insert
    local new_rt = new_info.return_type
    
    -- Formatting logic
    -- If we have specifiers, we want 1 space before type.
    -- If we don't, we might want 0 indentation or existing indentation?
    -- Actually replace_start_col from 'specifier end' usually points to right after the char.
    -- e.g. "virtual" end col is 11.
    -- Text replacement will start at 11.
    
    local replacement_text = ""
    if new_rt ~= "" then
        if found_specifier then
             -- "virtual[HERE]void Func"
             -- We want "virtual int Func"
             -- Insert " int "
             replacement_text = " " .. new_rt .. " "
        else
             -- "void Func"
             -- "int Func"
             -- Insert "int "
             -- Preserve indentation? 'replace_start_col' from container start includes indentation if container starts at indent?
             -- TS ranges exclude indentation? No, usually nodes start at first char.
             -- If container is field_declaration, it starts at first char.
             -- So indentation is BEFORE replace_start_col. We don't touch it.
             replacement_text = new_rt .. " "
        end
    else
        -- Constructor case (empty return type)
        -- "explicit MyClass"
        -- "MyClass"
        if found_specifier then
            replacement_text = " " -- Just a space "explicit MyClass"
        else
            replacement_text = ""
        end
    end
    
    -- Apply replacement
    vim.api.nvim_buf_set_text(target_buf, replace_start_row, replace_start_col, replace_end_row, replace_end_col, { replacement_text })
    
    logger.info("Updated declaration for %s (Params + Return Type).", new_info.func_name)
    
    vim.cmd("edit " .. vim.fn.fnameescape(vim.api.nvim_buf_get_name(target_buf)))
    vim.cmd(tostring(line_idx + 1))
    vim.cmd("normal! zz")
    return true
end

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
  

  -- 5. ヘッダーバッファの準備 (既存メソッドチェックのため必要)
  local target_buf = vim.fn.bufnr(header_file)
  if target_buf == -1 or not vim.api.nvim_buf_is_loaded(target_buf) then
      target_buf = vim.fn.bufadd(header_file)
      vim.fn.bufload(target_buf) 
  end

  -- 6. 既存チェック: Treesitterを使ってヘッダーを直接スキャン
  -- UNLのデータ（class_data）はファイルベースなので、未保存のバッファ変更やパース漏れがありうる
  -- バッファを直接見て、現在のコンテンツから同じ名前の関数があるか探す
  local ok, parser = pcall(vim.treesitter.get_parser, target_buf, "cpp")
  local matches = {}
  
  if ok and parser then
      local tree = parser:parse()[1]
      local root = tree:root()
      
      -- クラスの範囲を特定（UNLの行情報を使うか、改めて探す）
      -- UNLの class_data.line / end_line は参考になるが、ずれている可能性もある
      -- ここでは簡易的にファイル全体から関数名を探す
      -- （厳密には対象クラス内限定にすべきだが、同名のグローバル関数や他クラスメソッドへの誤爆リスクは低いと仮定）
      -- もし厳密にやるなら、rootからclass_data.nameを持つclass_specifierを探し、その中で探すべき。
      
      -- UNLの情報を信頼してクラスノードを探す
      local class_node = root:named_descendant_for_range(class_data.line - 1, 0, class_data.end_line - 1, 0)
      -- もしclass_nodeがクラスでなければ、親をたどる
      while class_node do
           if class_node:type() == "class_specifier" or class_node:type() == "struct_specifier" then break end
           class_node = class_node:parent()
      end
      
      if not class_node then class_node = root end -- Fallback to full file if class node logic fails
      
      local query_str = string.format([[
        (function_declarator declarator: (identifier) @name (#eq? @name "%s"))
        (function_declarator declarator: (field_identifier) @name (#eq? @name "%s"))
        (function_declarator declarator: (destructor_name) @name (#eq? @name "%s"))
      ]], info.func_name, info.func_name, info.func_name)
      
      local query = vim.treesitter.query.parse("cpp", query_str)
      for id, node, _ in query:iter_captures(class_node, target_buf, 0, -1) do
          local r, _, _, _ = node:range()
          table.insert(matches, {
              name = info.func_name,
              line = r + 1 -- 1-based line number for consistency
          })
      end
  else
      -- Fallback to UNL data if treesitter fails
      local existing_methods = flatten_methods(class_data)
      for _, m in ipairs(existing_methods) do
          if m.name == info.func_name then
              table.insert(matches, m)
          end
      end
  end
  
  if #matches == 1 then
      -- UPDATE MODE
      local target_m = matches[1]
      logger.info("Function '%s' found in header (line %d). Updating declaration...", info.func_name, target_m.line)
      update_declaration_in_header(target_buf, target_m, info, logger)
      return
  end
  
  if #matches > 1 then
      logger.warn("Multiple overloads found for '%s'. Cannot auto-update declaration safely.", info.func_name)
      -- TODO: Show picker?
      return
  end

  -- INSERT MODE (New Declaration)
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

  -- 書き込み (Insert Mode)
  vim.api.nvim_buf_set_lines(target_buf, insert_line, insert_line, false, { decl_code })
  
  -- ヘッダーを開いて移動
  vim.cmd("edit " .. vim.fn.fnameescape(header_file))
  vim.api.nvim_win_set_cursor(0, { insert_line + 1, 0 })
  vim.cmd("normal! zz")
  
  logger.info("Declaration created in %s", vim.fn.fnamemodify(header_file, ":t"))
end

return M
