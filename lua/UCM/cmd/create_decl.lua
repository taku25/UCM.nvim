-- lua/UCM/cmd/create_decl.lua
-- ソースファイル(.cpp)内の実装から、ヘッダーファイル(.h)に宣言を作成する

local ucm_log = require("UCM.logger")
local cmd_core = require("UCM.cmd.core")
local unl_api = require("UNL.api")

local M = {}

-- ヘルパー: メソッドリストをフラットにする
local function flatten_methods(class_data)
    local list = {}
    if not class_data or not class_data.methods then return list end
    for _, access in ipairs({"public", "protected", "private", "impl"}) do
        if class_data.methods[access] then
            for _, m in ipairs(class_data.methods[access]) do
                table.insert(list, m)
            end
        end
    end
    return list
end

-- 現在のバッファからターゲットと近傍関数を探す
local function find_neighbors(symbols, line)
    local target, prev_m, next_m = nil, nil, nil
    local flat_impls = {}
    for _, cls in ipairs(symbols) do
        for _, m in ipairs(cls.methods.impl or {}) do
            table.insert(flat_impls, { name = m.name, line = m.line, class_name = cls.name })
        end
    end
    table.sort(flat_impls, function(a, b) return a.line < b.line end)
    for i, m in ipairs(flat_impls) do
        if m.line == line then
            target = m
            if i > 1 then prev_m = flat_impls[i-1] end
            if i < #flat_impls then next_m = flat_impls[i+1] end
            break
        end
    end
    -- 名前だけで比較するため、必要な情報だけ返す
    return target, prev_m, next_m
end

function M.execute()
  local logger = ucm_log.get()
  local current_file = vim.api.nvim_buf_get_name(0)
  
  if not (current_file:match("%.cpp$") or current_file:match("%.c$")) then
      logger.warn("Create Declaration only works in source files.")
      return
  end

  local pair, _ = cmd_core.resolve_class_pair(current_file)
  if not pair or not pair.h then
      return logger.warn("Could not find corresponding header (.h) file.")
  end
  local header_file = pair.h
  local current_line = vim.fn.line(".")

  -- 1. 現在のバッファをサーバーでパースして近傍を取得
  unl_api.db.parse_buffer(nil, function(res)
      if not res or not res.symbols then
          return logger.error("Failed to parse current buffer via server.")
      end

      local info, prev_info, next_info = find_neighbors(res.symbols, current_line)
      if not info then
          return logger.warn("Could not find function implementation at line %d.", current_line)
      end

      -- 補完用データ構築
      local target_info = nil
      for _, cls in ipairs(res.symbols) do
          if cls.name == info.class_name then
              for _, m in ipairs(cls.methods.impl) do
                  if m.line == current_line then
                      target_info = {
                          class_name = cls.name,
                          func_name = m.name,
                          return_type = m.return_type or "void",
                          params = m.detail or "()"
                      }
                      break
                  end
              end
          end
      end

      logger.info("Extracting: %s::%s", target_info.class_name, target_info.func_name)

      -- 2. ヘッダーファイルの情報を取得
      unl_api.db.get_file_symbols(header_file, function(h_symbols)
          local class_data = nil
          if h_symbols then
              for _, s in ipairs(h_symbols) do
                  if s.name == target_info.class_name or s.name:match("^[A-Z]" .. target_info.class_name .. "$") then
                      class_data = s; break
                  end
              end
          end

          if not class_data then
              return logger.error("Class declaration for '%s' not found in %s.", target_info.class_name, header_file)
          end

          -- 3. 挿入位置の決定
          local target_buf = vim.fn.bufnr(header_file)
          if target_buf == -1 or not vim.api.nvim_buf_is_loaded(target_buf) then
              target_buf = vim.fn.bufadd(header_file)
              vim.fn.bufload(target_buf) 
          end

          local h_methods = flatten_methods(class_data)
          local insert_line = -1

          -- 近傍に基づいたスマートな位置特定
          if prev_info then
              for _, m in ipairs(h_methods) do
                  if m.name == prev_info.name then
                      insert_line = m.line -- 前の関数の宣言の直後に挿入
                      break
                  end
              end
          end

          if insert_line == -1 and next_info then
              for _, m in ipairs(h_methods) do
                  if m.name == next_info.name then
                      insert_line = m.line - 1 -- 次の関数の宣言の直前に挿入
                      break
                  end
              end
          end

          -- どちらも見つからない場合はクラスの末尾
          if insert_line == -1 then
              insert_line = (class_data.end_line or class_data.line + 1) - 1
          end

          -- 4. 既存チェック
          for _, m in ipairs(h_methods) do
              if m.name == target_info.func_name then
                  return logger.warn("Function '%s' already exists in header (line %d).", target_info.func_name, m.line)
              end
          end

          -- 5. 書き込み
          local decl_code = string.format("\t%s %s%s;", target_info.return_type, target_info.func_name, target_info.params)
          vim.api.nvim_buf_set_lines(target_buf, insert_line, insert_line, false, { decl_code })
          
          vim.cmd("edit " .. vim.fn.fnameescape(header_file))
          vim.api.nvim_win_set_cursor(0, { insert_line + 1, 0 })
          vim.cmd("normal! zz")
          logger.info("Declaration created in %s via smart positioning", vim.fn.fnamemodify(header_file, ":t"))
      end)
  end)
end

return M
