-- lua/UCM/cmd/create_impl.lua
-- ヘッダーファイル(.h)内の宣言から、ソースファイル(.cpp)に実装を作成する

local ucm_log = require("UCM.logger")
local cmd_core = require("UCM.cmd.core")
local unl_api = require("UNL.api")

local M = {}

-- 引数リスト文字列から、引数名のみを抽出する
local function extract_arg_names(params_str)
    if not params_str or params_str == "()" or params_str == "" then return "" end
    local content = params_str:match("^%s*%(?(.-)%)?%s*$")
    if not content or content == "" then return "" end
    local args = {}
    for param in content:gmatch("[^,]+") do
        local param_no_default = param:gsub("=.*$", ""):gsub("%[.*%]", "")
        local name = param_no_default:match("([%w_]+)%s*$")
        if name then table.insert(args, name) end
    end
    return table.concat(args, ", ")
end

-- 現在のバッファからターゲットと近傍宣言を探す
local function find_neighbors(symbols, line)
    local target, prev_m, next_m = nil, nil, nil
    local flat_decls = {}
    for _, cls in ipairs(symbols) do
        for _, access in ipairs({"public", "protected", "private"}) do
            for _, m in ipairs(cls.methods[access] or {}) do
                table.insert(flat_decls, { name = m.name, line = m.line, class_name = cls.name })
            end
        end
    end
    table.sort(flat_decls, function(a, b) return a.line < b.line end)
    for i, m in ipairs(flat_decls) do
        if m.line == line then
            target = m
            if i > 1 then prev_m = flat_decls[i-1] end
            if i < #flat_decls then next_m = flat_decls[i+1] end
            break
        end
    end
    return target, prev_m, next_m
end

function M.execute()
  local logger = ucm_log.get()
  local current_file = vim.api.nvim_buf_get_name(0)
  
  if not (current_file:match("%.h$") or current_file:match("%.hpp$")) then
      logger.warn("Create Implementation only works in header files.")
      return
  end
  
  cmd_core.resolve_class_pair(current_file, function(pair, err)
      if not pair or not pair.cpp then
          return logger.warn("Could not find corresponding source (.cpp) file.")
      end
      local cpp_file = pair.cpp
      local current_line = vim.fn.line(".")

      -- 1. 現在のヘッダーをパースして近傍を取得
      unl_api.db.parse_buffer(nil, function(res)
          if not res or not res.symbols then
              return logger.error("Failed to parse current buffer via server.")
          end

          local info, prev_info, next_info = find_neighbors(res.symbols, current_line)
          if not info then
              return logger.warn("Could not find function declaration at line %d.", current_line)
          end

          -- ターゲットの詳細データ取得
          local target_info = nil
          for _, cls in ipairs(res.symbols) do
              if cls.name == info.class_name then
                  for _, access in ipairs({"public", "protected", "private"}) do
                      for _, m in ipairs(cls.methods[access]) do
                          if m.line == current_line then target_info = m; break end
                      end
                      if target_info then break end
                  end
              end
              if target_info then target_info.class_name = cls.name; break end
          end

          logger.info("Generating implementation for %s::%s...", target_info.class_name, target_info.name)
          
          -- 2. ソースファイルの情報を取得して挿入位置を決定
          unl_api.db.get_file_symbols(cpp_file, function(cpp_symbols)
              local insert_line = -1
              local target_class_in_cpp = nil
              
              if cpp_symbols then
                  for _, cls in ipairs(cpp_symbols) do
                      if cls.name == target_info.class_name then
                          target_class_in_cpp = cls; break
                      end
                  end
              end

              if target_class_in_cpp then
                  -- 同じクラス内での近傍検索
                  local impls = target_class_in_cpp.methods.impl or {}
                  
                  if prev_info and prev_info.class_name == target_info.class_name then
                      for _, m in ipairs(impls) do
                          if m.name == prev_info.name then
                              insert_line = m.end_line or m.line; break
                          end
                      end
                  end
                  
                  if insert_line == -1 and next_info and next_info.class_name == target_info.class_name then
                      for _, m in ipairs(impls) do
                          if m.name == next_info.name then
                              insert_line = m.line - 1; break
                          end
                      end
                  end
                  
                  -- どちらも見つからないが、クラスの他の関数がある場合、その末尾へ
                  if insert_line == -1 and #impls > 0 then
                      table.sort(impls, function(a,b) return a.line < b.line end)
                      insert_line = impls[#impls].end_line or impls[#impls].line
                  end
              end

              -- 3. 実装コード生成
              local ret_type = target_info.return_type or ""
              if ret_type ~= "" then ret_type = ret_type .. " " end
              local clean_params = (target_info.params or "()"):gsub("%s*=%s*[^,%)%s]+", ""):gsub("%s*=%s*[^,%)%s]*%b()", "")
              local signature = string.format("%s%s::%s%s", ret_type, target_info.class_name, target_info.name, clean_params)
              
              local body = ""
              if target_info.flags and target_info.flags:find("override") then
                  local args = extract_arg_names(target_info.params)
                  body = (target_info.return_type == "void" or not target_info.return_type)
                      and string.format("    Super::%s(%s);\n", target_info.name, args)
                      or string.format("    return Super::%s(%s);\n", target_info.name, args)
              end
              
              local impl_code = string.format("\n%s\n{\n%s}\n", signature, body)
              local lines_to_append = vim.split(impl_code, "\n")

              -- 4. 書き込み
              local target_buf = vim.fn.bufnr(cpp_file)
              if target_buf == -1 or not vim.api.nvim_buf_is_loaded(target_buf) then
                  target_buf = vim.fn.bufadd(cpp_file)
                  vim.fn.bufload(target_buf) 
              end

              if insert_line == -1 then
                  -- クラス情報も近傍も見つからない場合はファイルの末尾
                  insert_line = vim.api.nvim_buf_line_count(target_buf)
              end
              
              vim.api.nvim_buf_set_lines(target_buf, insert_line, insert_line, false, lines_to_append)
              vim.cmd("edit " .. vim.fn.fnameescape(cpp_file))
              vim.api.nvim_win_set_cursor(0, { insert_line + #lines_to_append - 1, 0 })
              vim.cmd("normal! zz")
              logger.info("Implementation created in %s (line %d)", vim.fn.fnamemodify(cpp_file, ":t"), insert_line + 1)
          end)
      end)
  end)
end

return M