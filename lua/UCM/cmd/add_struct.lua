-- lua/UCM/cmd/add_struct.lua
local ucm_log = require("UCM.logger")
local ucm_config = require("UCM.config")
local unl_picker = require("UNL.backend.picker")
local provider = require("UNL.provider") -- UNL provider system

local M = {}

local function generate_struct_code(name, parent)
  local lines = {}
  table.insert(lines, "USTRUCT(BlueprintType)")
  
  if parent and parent ~= "" then
      table.insert(lines, string.format("struct %s : public %s", name, parent))
  else
      table.insert(lines, string.format("struct %s", name))
  end
  
  table.insert(lines, "{")
  table.insert(lines, "    GENERATED_BODY()")
  table.insert(lines, "")
  table.insert(lines, string.format("    %s();", name)) -- Constructor declaration
  table.insert(lines, "};")
  
  return lines
end

function M.run(opts)
  opts = opts or {}
  local logger = ucm_log.get()

  -- 1. Ask for Struct Name
  vim.ui.input({ prompt = "Struct Name (e.g. FMyStruct): " }, function(struct_name)
    if not struct_name or struct_name == "" then
       logger.warn("Struct name is required.")
       return
    end

    -- 2. Ask for Parent Struct (Optional, via Picker)
    -- We can fetch suggestions via UEP provider!
    local ok_provider, all_structs = provider.request("uep.get_project_structs", { scope = "all" })
    
    local items = {}
    if ok_provider and all_structs then
        for _, s in ipairs(all_structs) do
            table.insert(items, s.name)
        end
    end
    -- Add generic/commonly used base structs manually if needed, or rely on UEP
    table.insert(items, 1, "None (Simple Struct)")
    table.insert(items, 2, "FTableRowBase")
    
    -- De-duplicate
    local unique_items = {}
    local seen = {}
    local final_list = {}
    for _, name in ipairs(items) do
        if not seen[name] then
            seen[name] = true
            table.insert(final_list, name)
        end
    end

    unl_picker.pick({
        title = "Select Parent Struct (Optional)",
        items = final_list,
        conf = ucm_config.get(),
        on_submit = function(selected)
            local parent = selected
            if not parent or parent == "None (Simple Struct)" then parent = nil end
            
            -- 3. Generate Code
            local code_lines = generate_struct_code(struct_name, parent)
            
            -- 4. Insert at Cursor
            vim.api.nvim_put(code_lines, "l", true, true)
            logger.info("Inserted struct definition: %s", struct_name)
        end,
        -- If user aborts picker, maybe assume no parent?
        on_close = function()
             -- Optional: could allow aborting completely or defaulting to no parent
        end
    })
  end)
end

return M
