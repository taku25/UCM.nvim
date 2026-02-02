-- lua/UCM/cmd/new_struct.lua
-- Struct creation command - follows the same pattern as new.lua for classes

local unl_picker = require("UNL.backend.picker")
local selectors = require("UCM.selector")
local cmd_core = require("UCM.cmd.core")
local path = require("UCM.path")
local log = require("UCM.logger")
local fs = require("vim.fs")
local unl_events = require("UNL.event.events")
local unl_event_types = require("UNL.event.types")
local open_util = require("UNL.buf.open")

local function get_config()
  return require("UNL.config").get("UCM")
end

local M = {}

-- Process template file by replacing placeholders
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
  if vim.fn.filereadable(validation_opts.header_path) == 1 then
    return false, "Struct file already exists at: " .. validation_opts.header_path
  end
  
  local dir = fs.dirname(validation_opts.header_path)
  local test_file_path = fs.joinpath(dir, ".ucm_write_test")
  local file, err = io.open(test_file_path, "w")
  if not file then
    return false, string.format("Permission denied in destination directory: %s (Reason: %s)", dir, tostring(err))
  end
  file:close()
  pcall(vim.loop.fs_unlink, test_file_path)

  if vim.fn.filereadable(validation_opts.header_template) ~= 1 then
    return false, "Template file not found: " .. validation_opts.header_template
  end
  
  return true, nil
end

local function prepare_creation_plan(opts, conf)
  local context, err = cmd_core.resolve_creation_context(opts.target_dir)
  if not context then return nil, err end

  -- Use selector for struct template selection if parent_struct is specified
  local template_def
  if opts.parent_struct and opts.parent_struct ~= "" and opts.parent_struct ~= "None" then
    template_def = selectors.template.select_struct(opts.parent_struct, conf, opts.struct_data_map)
  else
    template_def = conf.struct_template or {
      name = "Struct",
      header_template = "Struct.h.tpl",
      struct_prefix = "F",
    }
  end

  local template_base_path = path.get_plugin_root_path("UCM") or ""
  template_base_path = fs.joinpath(template_base_path, "templates")

  local header_path = fs.joinpath(context.header_dir, opts.struct_name .. ".h")

  return {
    opts = opts,
    conf = conf,
    context = context,
    template_def = template_def,
    template_base_path = template_base_path,
    header_path = header_path,
  }, nil
end

-- Build inheritance part for struct
local function build_struct_inheritance(parent_struct)
  if not parent_struct or parent_struct == "" or parent_struct == "None" then
    return ""
  end
  return "\n\t: public " .. parent_struct
end

local function execute_file_creation(plan)
  local on_complete_callback = plan.opts.on_complete

  local function publish_and_return_error(message)
    unl_events.publish(unl_event_types.ON_AFTER_NEW_STRUCT_FILE, { status = "failed" })
    log.get().error(message)
    if on_complete_callback and type(on_complete_callback) == "function" then
      vim.schedule(function()
        on_complete_callback(false, { status = "failed", error = message })
      end)
    end
  end

  local header_template_path = fs.joinpath(plan.template_base_path, plan.template_def.header_template)

  local is_valid, validation_err = validate_creation_operation({
    header_path = plan.header_path,
    header_template = header_template_path,
  })
  if not is_valid then return publish_and_return_error(validation_err) end

  local struct_prefix = (plan.template_def and plan.template_def.struct_prefix) or "F"

  local parent_include = ""
  local struct_inheritance = ""
  if plan.opts.parent_struct and plan.opts.parent_struct ~= "" and plan.opts.parent_struct ~= "None" then
    parent_include = '#include "' .. plan.opts.parent_struct .. '.h"'
    struct_inheritance = "\n\t: public " .. plan.opts.parent_struct
  end

  local replacements = {
    STRUCT_NAME = plan.opts.struct_name,
    STRUCT_PREFIX = struct_prefix,
    PARENT_STRUCT = plan.opts.parent_struct or "",
    PARENT_INCLUDE = parent_include,
    STRUCT_INHERITANCE = struct_inheritance,
    MODULE_API = plan.context.module.name:upper() .. "_API",
  }

  local header_content, h_err = process_template(header_template_path, vim.tbl_extend('keep', { COPYRIGHT_HEADER = plan.conf.copyright_header_h }, replacements))
  if not header_content then return publish_and_return_error(h_err) end

  local write_ok, write_err = write_file(plan.header_path, header_content)
  if not write_ok then return publish_and_return_error(write_err) end

  log.get().info("Created struct '%s' at %s", plan.opts.struct_name, plan.header_path)

  unl_events.publish(unl_event_types.ON_AFTER_NEW_STRUCT_FILE, { status = "success", file = plan.header_path })

  if on_complete_callback and type(on_complete_callback) == "function" then
    vim.schedule(function()
      on_complete_callback(true, { status = "success", file = plan.header_path })
      open_util.open_buffer(plan.header_path, { focus = true })
    end)
  else
    vim.schedule(function()
      open_util.open_buffer(plan.header_path, { focus = true })
    end)
  end
end

function M.run(opts)
  opts = opts or {}
  local conf = get_config()

  if opts.struct_name and opts.parent_struct then
    -- Non-interactive mode
    local final_opts = {
      struct_name = opts.struct_name,
      parent_struct = opts.parent_struct or "",
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
      local prompt = string.format("Create struct '%s'?\n\nHeader: %s",
        plan.opts.struct_name, plan.header_path)
      local choices = "&Yes, create files\n&No, cancel"
      local decision = vim.fn.confirm(prompt, choices)

      if decision == 1 then
        execute_file_creation(plan)
      else
        log.get().info("Struct creation canceled.")
      end
    end
    return
  end

  log.get().debug("UI mode: UCM new_struct")
  local base_dir = opts.target_dir or vim.loop.cwd()
  local collected_opts = { on_complete = opts.on_complete }

  local show_picker -- Forward declaration

  local function ask_for_parent_struct()
    local struct_data_map = {}
    local static_choices = {
      { value = "None", label = "None (Simple Struct)", filename = "" },
      { value = "FTableRowBase", label = "FTableRowBase", filename = "" },
    }

    local dynamic_choices = {}
    local seen_structs = {}
    local unl_api_ok, unl_api = pcall(require, "UNL.api")
    if unl_api_ok then
      log.get().info("Fetching project structs from UNL.db...")
      
      unl_api.db.get_classes({ extra_where = "AND (c.symbol_type = 'struct' OR c.symbol_type = 'USTRUCT')" }, function(structs, err)
          if err then
              log.get().error("Error getting structs: " .. tostring(err))
              structs = nil
          end
          
          if structs and #structs > 0 then
            log.get().info("Successfully fetched %d structs.", #structs)
            for _, struct_info in ipairs(structs) do
              local s_name = struct_info.name
              local file_path = struct_info.path
              
              if s_name and not seen_structs[s_name] and s_name:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
                  table.insert(dynamic_choices, {
                    value = s_name,
                    label = string.format("%s - %s", s_name, vim.fn.fnamemodify(file_path, ":t")),
                    filename = file_path,
                  })
                  seen_structs[s_name] = true
                  struct_data_map[s_name] = {
                    header_file = file_path,
                    base_struct = struct_info.base_class
                  }
              end
            end
          else
            log.get().info("No struct data from UNL.db.")
          end
          
          show_picker(dynamic_choices, static_choices, struct_data_map)
      end)
      return -- Exit, wait for async callback
    else
      log.get().info("UNL.api not available.")
      show_picker(dynamic_choices, static_choices, struct_data_map)
    end
  end

  -- Move picker logic to separate function to support async flow
  show_picker = function(dynamic_choices, static_choices, struct_data_map)
    table.sort(dynamic_choices, function(a, b) return a.value < b.value end)
    table.sort(static_choices, function(a, b) return a.value < b.value end)
    local all_choices = vim.list_extend(dynamic_choices, static_choices)

    log.get().debug("Total parent struct choices: %d (dynamic: %d, static: %d)", 
      #all_choices, #dynamic_choices, #static_choices)

    unl_picker.pick({
      kind = "ucm_select_parent_struct",
      title = "  Select Parent Struct (or None)",
      items = all_choices,
      conf = conf,
      logger_name = "UCM",
      preview_enabled = true,

      on_submit = function(selected)
        if not selected then return log.get().info("Struct creation canceled.") end
        
        if selected == "None" then
          collected_opts.parent_struct = ""
        else
          collected_opts.parent_struct = selected
        end

        collected_opts.struct_data_map = struct_data_map

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
          local prompt = string.format("Create struct '%s'?\n\nHeader: %s",
            plan.opts.struct_name, plan.header_path)
          local choices = "&Yes, create files\n&No, cancel"
          local decision = vim.fn.confirm(prompt, choices)

          if decision == 1 then
            execute_file_creation(plan)
          else
            log.get().info("Struct creation canceled.")
          end
        end
      end,
    })
  end

  local function ask_for_struct_name_and_path()
    vim.ui.input({ prompt = "Enter Struct Name (e.g., MyStruct or path/to/MyStruct):" }, function(user_input)
      if not user_input or user_input == "" then
        return log.get().info("Struct creation canceled.")
      end
      local sanitized_input = user_input:gsub("\\", "/")
      local struct_name = vim.fn.fnamemodify(sanitized_input, ":t")
      local subdir_path = vim.fn.fnamemodify(sanitized_input, ":h")
      collected_opts.struct_name = struct_name
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
      ask_for_parent_struct()
    end)
  end

  ask_for_struct_name_and_path()
end

return M
