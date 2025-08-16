-- lua/UCM/cmd/new.lua

local selectors = require("UCM.selector")
local cmd_core = require("UCM.cmd.core")
local path = require("UCM.path")
local logger = require("UCM.logger")
local conf = require("UCM.conf") -- ★ conf を require する
local fs = require("vim.fs")

local M = {}

-- (ヘルパー関数 process_template, write_file は変更なし)
local function process_template(template_path, replacements)
  if vim.fn.filereadable(template_path) ~= 1 then return nil, "Template file not found: " .. template_path end
  local ok, lines = pcall(vim.fn.readfile, template_path); if not ok then return nil, "Failed to read template: " .. tostring(lines) end
  local content = table.concat(lines, "\n")
  for key, value in pairs(replacements) do content = content:gsub("{{" .. key .. "}}", tostring(value or "")) end
  return content, nil
end

local function write_file(file_path, content)
  local dir = vim.fn.fnamemodify(file_path, ":h"); if vim.fn.isdirectory(dir) ~= 1 then vim.fn.mkdir(dir, "p") end
  local ok, file = pcall(io.open, file_path, "w"); if not ok or not file then return false, "Failed to open file for writing: " .. tostring(file) end
  local write_ok, err = pcall(function() file:write(content) end); file:close()
  if not write_ok then return false, "Failed to write to file: " .. tostring(err) end
  return true, nil
end

---
-- @param opts table
-- @param on_complete function: A callback function(ok, result) to be called on completion.
function M.run(opts, on_complete)
  -- Step 1: Gather all information needed for file creation
  local context, err = cmd_core.resolve_creation_context(opts.target_dir)
  if not context then return on_complete(false, err) end

  local template_def = selectors.tpl.select(opts.parent_class)
  if not template_def then return on_complete(false, "No suitable template found for parent class: " .. opts.parent_class) end

  -- (テンプレート処理部分は変更なし、ただし results テーブルに情報を追加)
  local api_macro = context.module.name:upper() .. "_API"
  local common_replacements = { CLASS_NAME = opts.class_name, PARENT_CLASS = opts.parent_class, API_MACRO = api_macro, CLASS_PREFIX = template_def.class_prefix or "U", UCLASS_SPECIFIER = template_def.uclass_specifier or "", BASE_CLASS_NAME = template_def.base_class_name or opts.parent_class }
  local file_specific_info = { header = { template_file = template_def.header_template, output_dir = context.header_dir, output_extension = ".h", direct_includes = template_def.direct_includes, copyright = conf.active_config.copyright_header_h }, source = { template_file = template_def.source_template, output_dir = context.source_dir, output_extension = ".cpp", direct_includes = { string.format('"%s.h"', opts.class_name) }, copyright = conf.active_config.copyright_header_cpp } }
  local template_base_path = path.get_template_base_path(template_def, "UCM"); if not template_base_path then return on_complete(false, "Could not determine template base path.") end
  local results = { template_used = template_def.name }
  for file_type, info in pairs(file_specific_info) do
    local replacements = vim.deepcopy(common_replacements)
    local includes_str = ""; if info.direct_includes and #info.direct_includes > 0 then includes_str = "#include " .. table.concat(info.direct_includes, "\n#include ") end
    replacements.DIRECT_INCLUDES = includes_str; replacements.COPYRIGHT_HEADER = info.copyright
    local template_path = fs.joinpath(template_base_path, info.template_file)
    local content, template_err = process_template(template_path, replacements); if not content then return on_complete(false, template_err) end
    results[file_type] = { path = fs.joinpath(info.output_dir, opts.class_name .. info.output_extension), content = content }
  end
  results.header_path = results.header.path; results.source_path = results.source.path

  -- Step 2: Define the actual file writing logic as a reusable function
  local function do_create_files()
    if vim.fn.filereadable(results.header.path) == 1 or vim.fn.filereadable(results.source.path) == 1 then return on_complete(false, "One or both class files already exist.") end
    local ok_h, err_h = write_file(results.header.path, results.header.content); if not ok_h then return on_complete(false, "Failed to write header file: " .. err_h) end
    local ok_s, err_s = write_file(results.source.path, results.source.content); if not ok_s then pcall(os.remove, results.header.path); return on_complete(false, "Failed to write source file: " .. err_s) end
    on_complete(true, results)
  end

  -- Step 3: Decide whether to show confirmation UI or create directly
  if conf.active_config.confirm_on_new == false then
    -- Confirmation is OFF, create files immediately.
    do_create_files()
  else
    -- Confirmation is ON, show the UI.
    local prompt_lines = {
      "Template: " .. results.template_used,
      "---",
      results.header.path,
      results.source.path,
    }
    local prompt_str = string.format("Create new class '%s'?", opts.class_name) .. "\n\n" .. table.concat(prompt_lines, "\n")

    vim.ui.select(
      { "Yes, create files", "No, cancel" },
      { prompt = prompt_str, format_item = function(item) return "  " .. item end },
      function(choice)
        if not choice or choice ~= "Yes, create files" then
          return on_complete(false, "canceled")
        end
        do_create_files()
      end
    )
  end
end

return M
