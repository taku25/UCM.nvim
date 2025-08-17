-- lua/UCM/cmd/new.lua

local selectors = require("UCM.selector")
local cmd_core = require("UCM.cmd.core")
local path = require("UCM.path")
local logger = require("UCM.logger")
local conf = require("UCM.conf")
local fs = require("vim.fs")

local M = {}

-- Helper function to process templates
local function process_template(template_path, replacements)
  if vim.fn.filereadable(template_path) ~= 1 then
    return nil, "Template file not found: " .. template_path
  end
  local ok, lines = pcall(vim.fn.readfile, template_path)
  if not ok then
    return nil, "Failed to read template: " .. tostring(lines)
  end
  local content = table.concat(lines, "\n")
  for key, value in pairs(replacements) do
    content = content:gsub("{{" .. key .. "}}", tostring(value or ""))
  end
  return content, nil
end

-- Helper function to write files
local function write_file(file_path, content)
  local dir = vim.fn.fnamemodify(file_path, ":h")
  if vim.fn.isdirectory(dir) ~= 1 then
    vim.fn.mkdir(dir, "p")
  end
  local ok, file = pcall(io.open, file_path, "w")
  if not ok or not file then
    return false, "Failed to open file for writing: " .. tostring(file)
  end
  local write_ok, err = pcall(function() file:write(content) end)
  file:close()
  if not write_ok then
    return false, "Failed to write to file: " .. tostring(err)
  end
  return true, nil
end

local function on_complete(result, opts)
  logger.info("Successfully created class: " .. result.class_name)
  logger.info(" -> Template used: " .. result.template_used)
  logger.info(" -> Header file: " .. result.header_path)
  logger.info(" -> Source file: " .. result.source_path)
  local open_setting = conf.active_config.auto_open_on_new
  if open_setting == "header" and result.header_path then
    vim.cmd("edit " .. vim.fn.fnameescape(result.header_path))
  elseif open_setting == "source" and result.source_path then
    vim.cmd("edit " .. vim.fn.fnameescape(result.source_path))
  elseif open_setting == "both" and result.header_path and result.source_path then
    vim.cmd("edit " .. vim.fn.fnameescape(result.header_path)); vim.cmd("vsplit " .. vim.fn.fnameescape(result.source_path))
  end


  --ユーザーのコンプリートも呼ぶ
  if opts.on_comple then
     opts.on_comple(result)
  end
end

local function on_cancel(result, opts)
  --ユーザーのキャンセルも呼ぶ
  logger.error("Operation failed: " .. tostring(result))
  if opts.on_cancel then
     opts.on_cancel(result)
  end
end

local function on_exit(result, opts)
  --ユーザーのキャンセルも呼ぶ
  logger.error("Operation failed: " .. tostring(result))
  if opts.on_exit then
     opts.on_exit(result)
  end
end

---
-- @param opts table: { class_name, parent_class, target_dir,  }
function M.run(opts)
  -- Step 1: Gather all information needed for file creation
  local context, err = cmd_core.resolve_creation_context(opts.target_dir)
  if not context then
    return on_exit(err, opts)
  end

  local template_def = selectors.tpl.select(opts.parent_class)
  if not template_def then
    return on_exit("No suitable template found for parent class: " .. opts.parent_class, opts)
  end

  -- Step 2: Prepare template content
  local api_macro = context.module.name:upper() .. "_API"
  
  -- ★ 安全な複数行フォーマット
  local common_replacements = {
    CLASS_NAME = opts.class_name,
    PARENT_CLASS = opts.parent_class,
    API_MACRO = api_macro,
    CLASS_PREFIX = template_def.class_prefix or "U",
    UCLASS_SPECIFIER = template_def.uclass_specifier or "",
    BASE_CLASS_NAME = template_def.base_class_name or opts.parent_class,
  }

  -- ★ 安全な複数行フォーマット
  local file_specific_info = {
    header = {
      template_file = template_def.header_template,
      output_dir = context.header_dir,
      output_extension = ".h",
      direct_includes = template_def.direct_includes,
      copyright = conf.active_config.copyright_header_h,
    },
    source = {
      template_file = template_def.source_template,
      output_dir = context.source_dir,
      output_extension = ".cpp",
      direct_includes = { string.format('"%s.h"', opts.class_name) },
      copyright = conf.active_config.copyright_header_cpp,
    },
  }

  local template_base_path = path.get_template_base_path(template_def, "UCM")
  if not template_base_path then
    return on_exit("Could not determine template base path.", opts)
  end

  local results = {
    template_used = template_def.name,
  }

  -- Step 3: Process templates loop
  for file_type, info in pairs(file_specific_info) do
    local replacements = vim.deepcopy(common_replacements)
    local includes_str = ""
    -- ★ 安全な複数行フォーマット
    if info.direct_includes and #info.direct_includes > 0 then
      includes_str = "#include " .. table.concat(info.direct_includes, "\n#include ")
    end
    replacements.DIRECT_INCLUDES = includes_str
    replacements.COPYRIGHT_HEADER = info.copyright

    local template_path = fs.joinpath(template_base_path, info.template_file)
    local content, template_err = process_template(template_path, replacements)
    if not content then
      return on_exit(template_err, opts)
    end
    -- ★ 安全な複数行フォーマット
    results[file_type] = {
      path = fs.joinpath(info.output_dir, opts.class_name .. info.output_extension),
      content = content,
    }
  end
  results.class_name = opts.class_name
  results.header_path = results.header.path
  results.source_path = results.source.path

  -- This function encapsulates the actual file writing logic.
  local function do_create_files()
    if vim.fn.filereadable(results.header.path) == 1 or vim.fn.filereadable(results.source.path) == 1 then
      return on_exit("One or both class files already exist.", opts)
    end
    local ok_h, err_h = write_file(results.header.path, results.header.content)
    if not ok_h then
      return on_exit("Failed to write header file: " .. err_h, opts)
    end
    local ok_s, err_s = write_file(results.source.path, results.source.content)
    if not ok_s then
      pcall(os.remove, results.header.path) -- Attempt to clean up
      return on_exit("Failed to write source file: " .. err_s, opts)
    end
    on_complete(results, opts) -- Success
  end

  -- Step 4: Decide whether to show confirmation UI or create directly.
  local should_confirm = conf.active_config.confirm_on_new

 if not should_confirm then
    do_create_files()
  else
    -- 最後の責任者として、最もリッチな情報を、ユーザーに提示する
    local prompt_lines = {
      "Will create the following files:",
      results.header_path,
      results.source_path,
    }
    local prompt_str = table.concat(prompt_lines, "\n")
    local yes_message = "Yes, create files"
    vim.ui.select({ yes_message, "No, cancel" }, { prompt = prompt_str }, function(choice)
      if not choice or choice ~= yes_message then
        return on_cancel("canceled", opts)
      end
      do_create_files()
    end)
  end
end

return M
