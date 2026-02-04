-- lua/UCM/cmd/symbols.lua
local unl_picker = require("UNL.backend.picker")
local unl_api = require("UNL.api")
local unl_buf_open = require("UNL.buf.open")
local ucm_config = require("UNL.config").get("UCM")
local log = require("UCM.logger")

local M = {}

-- 階層構造をフラットなリストに変換する関数
local function flatten_hierarchy(symbols, default_path)
  local flat_list = {}
  
  for _, item in ipairs(symbols) do
    item.file_path = item.file_path or default_path
    table.insert(flat_list, item)

    local k = (item.kind or ""):lower()
    if k == "uclass" or k == "class" or k == "ustruct" or k == "struct" or k == "uenum" or k == "enum" then
       
       if item.methods then
         for _, access in ipairs({"public", "protected", "private", "impl"}) do
           if item.methods[access] then
             for _, method in ipairs(item.methods[access]) do
               method.file_path = method.file_path or item.file_path
               table.insert(flat_list, method)
             end
           end
         end
       end

       if item.fields then
         for _, access in ipairs({"public", "protected", "private", "impl"}) do
           if item.fields[access] then
             for _, field in ipairs(item.fields[access]) do
               field.file_path = field.file_path or item.file_path
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
  local flat_symbols = flatten_hierarchy(symbols, file_path)
  local items = {}
  
  for _, item in ipairs(flat_symbols) do
    local kind = item.kind or "Unknown"
    local kind_lower = kind:lower()
    
    local icon = " "
    
    if kind_lower:find("function") then 
        icon = "󰊕 "
    elseif kind_lower:find("property") or kind_lower:find("field") then 
        icon = " " 
    elseif kind_lower:find("class") or kind_lower:find("struct") then 
        icon = "󰌗 " 
    elseif kind_lower:find("enum") then 
        icon = "En " 
    elseif kind_lower:find("implementation") then
        icon = " "
    end

    -- パスの正規化と行番号の数値化 (Telescope プレビューアのタイムアウト対策)
    local target_path = (item.file_path or file_path):gsub("\\", "/")
    local line_num = tonumber(item.line) or 1
    if line_num <= 0 then line_num = 1 end

    table.insert(items, {
      display = string.format("%s %-35s  (%s)", icon, item.name, kind),
      value = item,
      filename = target_path,
      lnum = line_num,
      col = 0,
      kind = kind,
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
    sorter_opts = { preserve_order = true },

    on_submit = function(selection)
      if not selection then return end
      
      local data = selection.value or selection
      local target_path = data.file_path or data.filename or selection.filename
      local target_line = data.line or data.lnum or selection.lnum

      if target_path then
          unl_buf_open.safe({ 
              file_path = target_path, 
              open_cmd = "edit", 
              plugin_name = "UCM" 
          })
      else
          log.get().warn("Jump target filename is nil.")
          return
      end
      
      if target_line then
          local line = tonumber(target_line)
          if line then
              pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
              vim.cmd("normal! zz")
          end
      end
    end
  })
end

function M.execute(opts)
  opts = opts or {}
  local target_file = opts.file_path or vim.api.nvim_buf_get_name(0)
  
  if target_file == "" then
    return log.get().warn("No file to parse.")
  end

  log.get().debug("Parsing symbols for: %s", target_file)

  unl_api.provider.request("ucm.get_file_symbols", {
      file_path = target_file
  }, function(ok, symbols)
      if ok and symbols then
          show_picker(target_file, symbols)
      else
          log.get().error("Failed to parse symbols for %s", target_file)
      end
  end)
end

return M
