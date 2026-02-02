local unl_picker = require("UNL.backend.picker")
local log = require("UCM.logger")
local unl_api = require("UNL.api")

local M = {}

function M.run(opts)
  -- 1. 名前入力
  local name = opts and opts.name or vim.fn.input("New class/struct name: ")
  if not name or name == "" then
    log.warn("No name provided.")
    return
  end

  -- 2. 親クラス/構造体選択
  local dynamic_choices = {}
  local seen = {}
  local class_data_map = {}
  local project_root = require("UNL.finder").project.find_project_root(vim.fn.getcwd())
  if project_root then
    unl_api.db.get_project_classes({ scope = "full" }, function(header_details, err)
      if header_details and next(header_details) then
        for file_path, details in pairs(header_details) do
          if details.classes then
            for _, info in ipairs(details.classes) do
              local s_name = info.name or info.class_name
              local symbol_type = info.symbol_type or info.type or ""
              if s_name and not seen[s_name] and s_name:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
                if symbol_type == "class" or symbol_type == "UCLASS" or symbol_type == "struct" or symbol_type == "USTRUCT" then
                  table.insert(dynamic_choices, {
                    value = s_name,
                    label = string.format("%s - %s", s_name, vim.fn.fnamemodify(file_path, ":t")),
                    filename = file_path,
                    symbol_type = symbol_type
                  })
                  seen[s_name] = true
                  class_data_map[s_name] = {
                    header_file = file_path,
                    base = info.base_class or info.base_struct
                  }
                end
              end
            end
          end
        end
      end
      
      -- Picker表示 (非同期完了後)
      M._internal_show_picker(dynamic_choices, class_data_map, name, opts)
    end)
  else
    -- ルートが見つからない場合、空リストで表示
    M._internal_show_picker(dynamic_choices, class_data_map, name, opts)
  end
end

function M._internal_show_picker(dynamic_choices, class_data_map, name, opts)
  local function on_parent_selected(choice)
    if not choice then return end
    local parent = choice.value
    local target_dir = opts and opts.target_dir or nil
    local is_struct = choice.symbol_type == "struct" or choice.symbol_type == "USTRUCT"
    if is_struct then
      require("UCM.cmd.new_struct").run({
        struct_name = name,
        parent_struct = parent,
        target_dir = target_dir,
        skip_confirmation = true
      })
    else
      require("UCM.cmd.new_class").run({
        class_name = name,
        parent_class = parent,
        target_dir = target_dir,
        skip_confirmation = true
      })
    end
  end

  unl_picker.pick({
    kind = "ucm_select_parent_class_or_struct",
    title = "  Select Parent Class or Struct",
    items = dynamic_choices,
    logger_name = "UCM",
    preview_enabled = true,
    on_submit = function(selected)
      if not selected then return end
      on_parent_selected(selected)
    end,
  })
end

return M
