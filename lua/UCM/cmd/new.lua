-- lua/UCM/cmd/new.lua

local unl_picker = require("UNL.backend.picker")
local selectors = require("UCM.selector")
local cmd_core = require("UCM.cmd.core")
local path = require("UCM.path")
local log = require("UCM.logger")
local fs = require("vim.fs")
local unl_events = require("UNL.event.events")
local unl_event_types = require("UNL.event.types")
-- (変更) 正しいモジュールを読み込む
local open_util = require("UNL.buf.open")

-- ... (これより上の部分は変更なし) ...
local function get_config()
  return require("UNL.config").get("UCM")
end

local M = {}

local function process_template(template_path, replacements)
  if vim.fn.filereadable(template_path) ~= 1 then
    return nil, "Template file not found: " .. template_path
  end
  local ok, lines = pcall(vim.fn.readfile, template_path)
  if not ok then return nil, "Failed to read template: " .. tostring(lines) end
  local content = table.concat(lines, "\n")
  for key, value in pairs(replacements) do
    content = content:gsub("{{" .. key .. "}}", tostring(value or ""))
  end
  return content, nil
end

local function write_file(file_path, content)
  local dir = vim.fn.fnamemodify(file_path, ":h")
  if vim.fn.isdirectory(dir) ~= 1 then vim.fn.mkdir(dir, "p") end
  local ok, file = pcall(io.open, file_path, "w")
  if not ok or not file then return false, "Failed to open file for writing: " .. tostring(file) end
  local write_ok, err = pcall(function() file:write(content) end)
  file:close()
  if not write_ok then return false, "Failed to write to file: " .. tostring(err) end
  return true, nil
end

local function validate_creation_operation(validation_opts)
  if vim.fn.filereadable(validation_opts.header_path) == 1 or vim.fn.filereadable(validation_opts.source_path) == 1 then
    return false, "One or both class files already exist at the destination."
  end
  for _, dir in ipairs({ fs.dirname(validation_opts.header_path), fs.dirname(validation_opts.source_path) }) do
    local test_file_path = fs.joinpath(dir, ".ucm_write_test")
    local file, err = io.open(test_file_path, "w")
    if not file then
      return false, string.format("Permission denied in destination directory: %s (Reason: %s)", dir, tostring(err))
    end
    file:close()
    pcall(vim.loop.fs_unlink, test_file_path)
  end
  for _, tpl_path in ipairs({ validation_opts.header_template, validation_opts.source_template }) do
    if vim.fn.filereadable(tpl_path) ~= 1 then
      return false, "Template file not found: " .. tpl_path
    end
  end
  return true, nil
end

local function prepare_creation_plan(opts, conf)
  local context, err = cmd_core.resolve_creation_context(opts.target_dir)
  if not context then return nil, err end

  local template_def = selectors.template.select(opts.parent_class, conf)
  if not template_def then return nil, "No suitable template found for: " .. opts.parent_class end

  local template_base_path = path.get_template_base_path(template_def, "UCM")
  if not template_base_path then return nil, "Could not determine template base path." end

  local header_path = fs.joinpath(context.header_dir, opts.class_name .. ".h")
  local source_path = fs.joinpath(context.source_dir, opts.class_name .. ".cpp")

  return {
    opts = opts,
    conf = conf,
    context = context,
    template_def = template_def,
    template_base_path = template_base_path,
    header_path = header_path,
    source_path = source_path,
  }, nil
end

local function execute_file_creation(plan)
  local on_complete_callback = plan.opts.on_complete

  local function publish_and_return_error(message)
    unl_events.publish(unl_event_types.ON_AFTER_NEW_CLASS_FILE, { status = "failed" })
    log.get().error(message)
    if on_complete_callback and type(on_complete_callback) == "function" then
      vim.schedule(function()
        on_complete_callback(false, { status = "failed", error = message })
      end)
    end
  end

  local header_template_path = fs.joinpath(plan.template_base_path, plan.template_def.header_template)
  local source_template_path = fs.joinpath(plan.template_base_path, plan.template_def.source_template)

  local is_valid, validation_err = validate_creation_operation({
    header_path = plan.header_path,
    source_path = plan.source_path,
    header_template = header_template_path,
    source_template = source_template_path,
  })
  if not is_valid then return publish_and_return_error(validation_err) end

  local new_class_prefix = (plan.template_def and plan.template_def.class_prefix)
    or (plan.opts.parent_class:match("^[AUFIS]"))
    or "U"

  local replacements = {
    CLASS_NAME = plan.opts.class_name,
    API_MACRO = plan.context.module.name:upper() .. "_API",
    CLASS_PREFIX = new_class_prefix,
    BASE_CLASS_NAME = plan.opts.parent_class,
    UCLASS_SPECIFIER = (plan.template_def and plan.template_def.uclass_specifier) or "",
    DIRECT_INCLUDES = (plan.template_def and plan.template_def.direct_includes and #plan.template_def.direct_includes > 0)
        and ("#include " .. table.concat(plan.template_def.direct_includes, "\n#include "))
      or ('#include "' .. plan.opts.parent_class .. '.h"'),
  }

  local header_content, h_err = process_template(header_template_path, vim.tbl_extend('keep', { COPYRIGHT_HEADER = plan.conf.copyright_header_h }, replacements))
  if not header_content then return publish_and_return_error(h_err) end

  local source_content, s_err = process_template(source_template_path, vim.tbl_extend('keep', { COPYRIGHT_HEADER = plan.conf.copyright_header_cpp }, replacements))
  if not source_content then return publish_and_return_error(s_err) end

  local ok_h, err_h = write_file(plan.header_path, header_content)
  if not ok_h then return publish_and_return_error("Failed to write header file: " .. err_h) end

  local ok_s, err_s = write_file(plan.source_path, source_content)
  if not ok_s then
    pcall(vim.loop.fs_unlink, plan.header_path)
    return publish_and_return_error("Failed to write source file: " .. err_s)
  end

  local success_payload = {
    status = "success",
    header_path = plan.header_path,
    source_path = plan.source_path,
    template_used = plan.template_def.name,
    module = plan.context.module,
  }
  unl_events.publish(unl_event_types.ON_AFTER_NEW_CLASS_FILE, success_payload)

  if on_complete_callback and type(on_complete_callback) == "function" then
    vim.schedule(function()
      on_complete_callback(true, success_payload)
    end)
  end

  log.get().info("Successfully created class: " .. plan.opts.class_name)

  -- ▼▼▼ ここからが今回の修正箇所 ▼▼▼
  local open_setting = plan.conf.auto_open_on_new
  if open_setting == "header" then
    open_util.safe({ file_path = plan.header_path, open_cmd = "edit", plugin_name = "UCM" })
  elseif open_setting == "source" then
    open_util.safe({ file_path = plan.source_path, open_cmd = "edit", plugin_name = "UCM" })
  elseif open_setting == "both" then
    open_util.safe({ file_path = plan.header_path, open_cmd = "edit", plugin_name = "UCM" })
    open_util.safe({ file_path = plan.source_path, open_cmd = "vsplit", plugin_name = "UCM" })
  end
  -- ▲▲▲ ここまでが今回の修正箇所 ▲▲▲
end


-- ... (これより下の M.run 関数は変更なし) ...
function M.run(opts)
  opts = opts or {}
  local conf = get_config()

  if opts.class_name and opts.parent_class then
    log.get().debug("Direct mode: UCM new")
    local final_opts = {
      class_name = opts.class_name,
      parent_class = opts.parent_class,
      target_dir = opts.target_dir or vim.loop.cwd(),
      on_complete = opts.on_complete,
    }
    local plan, err = prepare_creation_plan(final_opts, conf)
    if err then
      if final_opts.on_complete then
        pcall(final_opts.on_complete, false, { error = err })
      end
      return log.get().error(err)
    end
    if not conf.confirm_on_new then
        execute_file_creation(plan)
    else
      local prompt = string.format("Create class '%s'?\n\nHeader: %s\nSource: %s",
        plan.opts.class_name, plan.header_path, plan.source_path)
      local yes_choice = "Yes, create files"
      vim.ui.select({ yes_choice, "No, cancel" }, { prompt = prompt }, function(choice)
        if choice == yes_choice then
          execute_file_creation(plan)
        else
          log.get().info("Class creation canceled.")
        end
      end)
    end
    return
  end

  log.get().debug("UI mode: UCM new")
  local base_dir = opts.target_dir or vim.loop.cwd()
  local collected_opts = { on_complete = opts.on_complete }

  local function ask_for_parent_class()
    local static_choices = {}
    local seen_classes = {}
    for _, rule in ipairs(conf.template_rules) do
      local name = rule.base_class_name
      if name and not seen_classes[name] then
        table.insert(static_choices, {
          value = name,
          label = string.format("%-40s (%s)", name, "   Engine Template")
        })
        seen_classes[name] = true
      end
    end

    local dynamic_choices = {}
    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if unl_api_ok then
      log.get().info("Fetching project classes from UEP.nvim provider...")

      -- ▼▼▼ ここからが修正箇所 ▼▼▼
      -- 1. UEPプロバイダーを呼び出す前に、現在のプロジェクトルートを特定する
      local project_root = require("UNL.finder").project.find_project_root(base_dir)
      if not project_root then
          log.get().warn("Could not find project root from '%s'. Cannot fetch dynamic classes.", base_dir)
      end
      
      -- 2. UEPプロバイダーに、どのプロジェクトのクラス情報が必要かを明示的に伝える
      local req_ok, header_details = unl_api.provider.request("uep.get_project_classes", { 
        project_root = project_root, -- この情報を追加
        logger_name = "UCM" 
      })
      -- ▲▲▲ ここまでが修正箇所 ▲▲▲

      if req_ok and header_details and next(header_details) then
        log.get().info("Successfully fetched %d header details.", vim.tbl_count(header_details))
        for file_path, details in pairs(header_details) do
          if details.classes then
            for _, class_info in ipairs(details.classes) do
              if not seen_classes[class_info.class_name] and not class_info.is_final and not class_info.is_interface then
                table.insert(dynamic_choices, {
                  value = class_info.class_name,
                  label = string.format("%-40s (%s)   %s",
                    class_info.class_name,
                    class_info.base_class or "UObject",
                    vim.fn.fnamemodify(file_path, ":t"))
                })
                seen_classes[class_info.class_name] = true
              end
            end
          end
        end
      else
        log.get().info("Could not get class data from UEP.nvim. Using static template list only.")
      end
    else
      log.get().info("UNL.api not available. Using static template list only.")
    end

    table.sort(dynamic_choices, function(a, b) return a.value < b.value end)
    table.sort(static_choices, function(a, b) return a.value < b.value end)
    local all_choices = vim.list_extend(dynamic_choices, static_choices)

    unl_picker.pick({
      kind = "ucm_select_parent_class_combined",
      title = "  Select Parent Class",
      items = all_choices,
      conf = conf,
      logger_name = "UCM",
      preview_enabled = false,
      on_submit = function(selected)
        if not selected then return log.get().info("Class creation canceled.") end
        collected_opts.parent_class = selected
        
        local plan, err = prepare_creation_plan(collected_opts, conf)
        if err then
          if collected_opts.on_complete then
            pcall(collected_opts.on_complete, false, { error = err })
          end
          return log.get().error(err)
        end
        
        if not conf.confirm_on_new then
          execute_file_creation(plan)
        else
          local prompt = string.format("Create class '%s'?\n\nHeader: %s\nSource: %s",
            plan.opts.class_name, plan.header_path, plan.source_path)
          local yes_choice = "Yes, create files"
          vim.ui.select({ yes_choice, "No, cancel" }, { prompt = prompt }, function(choice)
            if choice == yes_choice then
              execute_file_creation(plan)
            else
              log.get().info("Class creation canceled.")
            end
          end)
        end
      end,
    })
  end

  local function ask_for_class_name_and_path()
    vim.ui.input({ prompt = "Enter Class Name (e.g., MyClass or path/to/MyClass):" }, function(user_input)
      if not user_input or user_input == "" then
        return log.get().info("Class creation canceled.")
      end
      local sanitized_input = user_input:gsub("\\", "/")
      local class_name = vim.fn.fnamemodify(sanitized_input, ":t")
      local subdir_path = vim.fn.fnamemodify(sanitized_input, ":h")
      collected_opts.class_name = class_name
      if subdir_path == "." or subdir_path == "" then
        collected_opts.target_dir = base_dir
      else
        collected_opts.target_dir = vim.fs.joinpath(base_dir, subdir_path)
      end
      log.get().debug("Validating target directory: %s", collected_opts.target_dir)
      local context, err = cmd_core.resolve_creation_context(collected_opts.target_dir)
      if not context then
        log.get().error(err)
        if collected_opts.on_complete and type(collected_opts.on_complete) == "function" then
          vim.schedule(function()
            collected_opts.on_complete(false, { status = "failed", error = err })
          end)
        end
        return
      end
      ask_for_parent_class()
    end)
  end

  ask_for_class_name_and_path()
end

return M
