-- lua/UCM/cmd/copy_imp.lua
local ucm_log = require("UCM.logger")
local unl_api = require("UNL.api")

local M = {}

-- パラメータリストから引数名だけを抽出するヘルパー (Lua側で補助的に実行)
local function extract_arg_names(params_text)
  local names = {}
  -- "(float DeltaTime, int32 Count = 0)" -> ["DeltaTime", "Count"]
  local clean = params_text:gsub("^%(", ""):gsub("%)$", "")
  for part in string.gmatch(clean, "([^,]+)") do
    -- デフォルト引数除去
    local decl = part:match("^([^=]+)") or part
    -- 型と変数名を分離 (最後の単語を変数名とみなす)
    -- 注意: ポインタや参照 (*, &) が変数名にくっついているケースを考慮
    local name = decl:match("([%w_]+)%s*$")
    if name then table.insert(names, name) end
  end
  return names
end

function M.execute()
  local log = ucm_log.get()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0) -- [row, col] (1-based)
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  
  log.info("Analyzing function signature via UNL server...")

  unl_api.db.parse_buffer({
    content = content,
    line = cursor[1] - 1,
    character = cursor[2],
    file_path = vim.api.nvim_buf_get_name(bufnr)
  }, function(result, err)
    if err or not result or not result.cursor_info or result.cursor_info == vim.NIL then
      return log.warn("Could not find function signature at cursor.")
    end

    local info = result.cursor_info
    local func_name = info.name
    local class_name = info.class_name
    local return_type = info.return_type or "void"
    local params_text = info.parameters or "()"
    local is_const = info.is_const
    local is_virtual = info.is_virtual or info.full_text:find("virtual") ~= nil
    local is_override = info.full_text:find("override") ~= nil

    if not func_name or func_name == "" then
      return log.warn("Function name not found.")
    end

    -- Super呼び出しの組み立て
    local arg_names = extract_arg_names(params_text)
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
      class_name ~= "" and class_name or "FMyClass", 
      func_name, 
      params_text,
      is_const and " const" or "",
      super_call
    )

    vim.fn.setreg('+', code)
    vim.fn.setreg('"', code)

    log.info("Copied: %s::%s", class_name, func_name)
    vim.notify("Copied implementation!", vim.log.levels.INFO)
  end)
end

return M