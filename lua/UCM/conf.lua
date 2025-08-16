-- lua/UCM/conf.lua

local M = {}

----------------------------------------------------------------------
-- 1. Default Configuration Options
----------------------------------------------------------------------
local defaults = {
  confirm_on_new = true,
  default_parent_class = "Actor",

  copyright_header_h = "// Copyright...",
  copyright_header_cpp = "// Copyright..",

  template_rules = {
    {
      name = "Actor",
      priority = 100,
      parent_regex = "^A",
      template_dir = "builtin",
      header_template = "Actor.h.tpl",
      source_template = "Actor.cpp.tpl",
      class_prefix = "A", -- ★ フラット化
      uclass_specifier = "", -- ★ フラット化
      base_class_name = "Actor", -- ★ フラット化
      direct_includes = { '"GameFramework/Actor.h"' }, -- ★ フラット化
    },
    {
      name = "Character",
      priority = 200,
      parent_regex = "^A.*Character$",
      template_dir = "builtin",
      header_template = "Character.h.tpl",
      source_template = "Character.cpp.tpl",
      class_prefix = "A",
      uclass_specifier = "",
      base_class_name = "Character",
      direct_includes = { '"GameFramework/Character.h"' },
    },
    -- PlayerCameraManager
    {
      name = "PlayerCameraManager",
      priority = 200,
      parent_regex = "^APlayerCameraManager$",
      template_dir = "builtin",
      header_template = "PlayerCameraManager.h.tpl", -- Dedicated or reuse UObjectClass
      source_template = "PlayerCameraManager.cpp.tpl",
      class_prefix = "A",
      uclass_specifier = "",
      base_class_name = "PlayerCameraManager",
      direct_includes = { '"Camera/PlayerCameraManager.h"' },
    },
    -- ActorComponent Class
    {
      name = "ActorComponent",
      priority = 100,
      parent_regex = ".*ActorComponent$",
      template_dir = "builtin",
      header_template = "ActorComponent.h.tpl",
      source_template = "ActorComponent.cpp.tpl",
      class_prefix = "U",
      uclass_specifier = "",
      base_class_name = "ActorComponent",
      direct_includes = { '"Components/ActorComponent.h"' },
    },
    -- SceneComponent Class
    {
      name = "SceneComponent",
      priority = 200,
      parent_regex = ".*SceneComponent$",
      template_dir = "builtin",
      header_template = "ActorComponent.h.tpl", -- Reuses ActorComponent template files
      source_template = "ActorComponent.cpp.tpl",
      class_prefix = "U",
      uclass_specifier = "",
      base_class_name = "SceneComponent",
      direct_includes = { '"Components/SceneComponent.h"' },
    },
    -- BlueprintLibrary Class
    {
      name = "BlueprintLibrary",
      priority = 200,
      parent_regex = ".*BlueprintFunctionLibrary$",
      template_dir = "builtin",
      header_template = "UObject.h.tpl", -- Reuses UObject template files
      source_template = "UObject.cpp.tpl",
      class_prefix = "U",
      uclass_specifier = "",
      base_class_name = "BlueprintFunctionLibrary",
      direct_includes = { '"Kismet/BlueprintFunctionLibrary.h"' },
    },
    -- GameModeBase Class
    {
      name = "GameModeBase",
      priority = 200,
      parent_regex = "^AGameModeBase$",
      template_dir = "builtin",
      header_template = "UObject.h.tpl",
      source_template = "UObject.cpp.tpl",
      class_prefix = "A",
      uclass_specifier = "",
      base_class_name = "GameModeBase",
      direct_includes = { '"GameFramework/GameModeBase.h"' },
    },
    -- Hud Class
    {
      name = "Hud",
      priority = 200,
      parent_regex = "^AHUD$",
      template_dir = "builtin",
      header_template = "UObject.h.tpl",
      source_template = "UObject.cpp.tpl",
      class_prefix = "A",
      uclass_specifier = "",
      base_class_name = "HUD",
      direct_includes = { '"GameFramework/HUD.h"' },
    },
    -- Interface Class
    {
      name = "Interface",
      priority = 200,
      parent_regex = "^I",
      template_dir = "builtin",
      header_template = "Interface.h.tpl",
      source_template = "Interface.cpp.tpl",
      class_prefix = "U", -- U for UInterface, but I for class name
      uclass_specifier = "MinimalAPI",
      base_class_name = "Interface",
      direct_includes = {}, -- UInterface does not include its base class
    },
    -- PlayerController Class
    {
      name = "PlayerController",
      priority = 200,
      parent_regex = "^APlayerController$",
      template_dir = "builtin",
      header_template = "UObject.h.tpl",
      source_template = "UObject.cpp.tpl",
      class_prefix = "A",
      uclass_specifier = "",
      base_class_name = "PlayerController",
      direct_includes = { '"GameFramework/PlayerController.h"' },
    },
    -- PlayerState Class
    {
      name = "PlayerState",
      priority = 200,
      parent_regex = "^APlayerState$",
      template_dir = "builtin",
      header_template = "UObject.h.tpl",
      source_template = "UObject.cpp.tpl",
      class_prefix = "A",
      uclass_specifier = "",
      base_class_name = "PlayerState",
      direct_includes = { '"GameFramework/PlayerState.h"' },
    },
    -- SlateWidget Class
    {
      name = "SlateWidget",
      priority = 200,
      parent_regex = "^S",
      template_dir = "builtin",
      header_template = "SlateWidget.h.tpl",
      source_template = "SlateWidget.cpp.tpl",
      class_prefix = "S",
      uclass_specifier = "",
      base_class_name = "", -- SWidget doesn't have a prefix like U or A
      direct_includes = { '"Widgets/SCompoundWidget.h"' },
    },
    -- SlateWidgetStyle Class
    {
      name = "SlateWidgetStyle",
      priority = 200,
      parent_regex = "^F.*WidgetStyle$",
      template_dir = "builtin",
      header_template = "SlateWidgetStyle.h.tpl",
      source_template = "SlateWidgetStyle.cpp.tpl",
      class_prefix = "F",
      uclass_specifier = "",
      base_class_name = "",
      direct_includes = { '"Styling/SlateWidgetStyle.h"' },
    },
    -- WorldSettings Class
    {
      name = "WorldSettings",
      priority = 200,
      parent_regex = "^AWorldSettings$",
      template_dir = "builtin",
      header_template = "UObject.h.tpl",
      source_template = "UObject.cpp.tpl",
      class_prefix = "A",
      uclass_specifier = "",
      base_class_name = "WorldSettings",
      direct_includes = { '"GameFramework/WorldSettings.h"' },
    },
    -- Generic UObject fallback (lowest priority)
    {
      name = "Object",
      priority = 1,
      parent_regex = "^U", -- Default for any UObject
      template_dir = "builtin",
      header_template = "UObject.h.tpl",
      source_template = "UObject.cpp.tpl",
      class_prefix = "U",
      uclass_specifier = "",
      base_class_name = "Object",
      direct_includes = { '"UObject/Object.h"' },
    },
    {
      name = "Object",
      priority = 0,
      parent_regex = ".*", -- Default for any UObject
      template_dir = "builtin",
      header_template = "UObject.h.tpl",
      source_template = "UObject.cpp.tpl",
      class_prefix = "U",
      uclass_specifier = "",
      base_class_name = "Object",
      direct_includes = { '"UObject/Object.h"' },
    },
  },

  folder_rules = {
    -- 各ルールは、headerとsourceのパス名を明示的に持つ
    { header = "Public", source = "Private" },
    { header = "Classes", source = "Sources" },
    -- ユーザーは、どんな非対称なルールも追加できる
    -- { header = "Includes", source = "Private" },
  },
  folder_rules = {
    -- Basic Public <-> Private mapping
    { type = "header",  regex = "^[Pp]ublic$", replacement = "Private" },
    { type = "source",  regex = "^[Pp]rivate$", replacement = "Public" },
    { type = "header",  regex = "^[Cc]lasses$", replacement = "Sources" },
    { type = "source",  regex = "^[Ss]ources$", replacement = "Classes" },
    
    -- Example of an asymmetric rule (as you pointed out)
    -- { regex = "^Headers$", replacement = "Private" },
    -- { regex = "^Private$", replacement = "Headers" },
  },
}

M.active_config = {}
M.user_config = {}

----------------------------------------------------------------------
-- 2. Helper Functions for Configuration Merging
----------------------------------------------------------------------

--- Deeply merges two tables, handling nested tables.
-- This is similar to vim.tbl_deep_extend("force"), but specifically tailored
-- for merging configuration objects with default values.
-- @param base_table table: The base table to merge into.
-- @param new_table table: The table with new values to merge from.
-- @return table: The deeply merged table.
local function deep_merge_tables(base_table, new_table)
  base_table = base_table or {}
  new_table = new_table or {}

  local merged = vim.deepcopy(base_table) -- Start with a deep copy of the base
  
  for k, v in pairs(new_table) do
    if type(v) == "table" and type(merged[k]) == "table" then
      -- If both are tables, recurse (deep merge)
      merged[k] = deep_merge_tables(merged[k], v)
    else
      -- Otherwise, overwrite
      merged[k] = v
    end
  end
  return merged
end

--- Merges two lists of rules (tables with a 'name' field) by name.
-- New rules with matching names overwrite base rules, and nested tables
-- within rules (like 'properties' or 'tokens') are deeply merged.
-- @param base_rules table: The base list of rules.
-- @param new_rules table: The new list of rules to merge in.
-- @return table: The merged list of rules.
local function merge_rules_by_name(base_rules, new_rules)
  base_rules = base_rules or {}
  new_rules = new_rules or {}

  if #new_rules == 0 then return base_rules end

  local by_name = {}
  -- Map base rules by name
  for _, r in ipairs(base_rules) do
    if r.name then by_name[r.name] = r end
  end
  
  -- Overwrite/add new rules, performing deep merge for nested tables
  for _, r in ipairs(new_rules) do
    if r.name then
      local existing_rule = by_name[r.name]
      if existing_rule then
        -- Deep merge properties and tokens
        r.properties = deep_merge_tables(existing_rule.properties, r.properties)
        r.tokens = deep_merge_tables(existing_rule.tokens, r.tokens)
        by_name[r.name] = r
      else
        by_name[r.name] = r
      end
    end
  end
  
  -- Reconstruct the list, preserving original order for base rules
  -- and appending new rules. This part can be complex if strict order matters.
  -- For simplicity, we'll just reconstruct based on the map.
  local final_merged = {}
  -- Add rules from base_rules that weren't overwritten
  for _, r in ipairs(base_rules) do
      if r.name and by_name[r.name] then
          table.insert(final_merged, by_name[r.name])
          by_name[r.name] = nil -- Mark as added
      end
  end
  -- Add any remaining new rules
  for _, r in ipairs(new_rules) do
      if r.name and by_name[r.name] then -- Check if it's a new rule not already added
          table.insert(final_merged, by_name[r.name])
          by_name[r.name] = nil -- Mark as added
      end
  end

  -- If order doesn't strictly matter and just unique names, simpler:
  -- local final_merged_unordered = {}
  -- for _, r in pairs(by_name) do table.insert(final_merged_unordered, r) end
  -- return final_merged_unordered

  return final_merged
end

--- Looks for and loads a `.ucmrc` file from the project root.
-- (This function remains unchanged from your previous implementation)
local function load_project_config(root_dir)
  -- ... (Your existing implementation) ...
  local config_file_path = root_dir .. "/" .. ".ucmrc"
  if vim.fn.filereadable(config_file_path) ~= 1 then return {}, nil end

  local read_ok, file_content_lines = pcall(vim.fn.readfile, config_file_path)
  if not read_ok or not file_content_lines then
    return nil, "UCM: Failed to read .ucmrc file: " .. tostring(file_content_lines)
  end

  local json_string = table.concat(file_content_lines, "\n")
  local decode_ok, decoded_json = pcall(vim.fn.json_decode, json_string)
  if not decode_ok or type(decoded_json) ~= "table" then
    return nil, "UCM: Invalid JSON in .ucmrc file: " .. tostring(decoded_json)
  end
  return decoded_json, nil
end

----------------------------------------------------------------------
-- 3. Core Configuration Functions
----------------------------------------------------------------------

function M.load_config(root_dir)
  local new_config = vim.deepcopy(defaults)

  -- Merge user options
  if M.user_config then
    for k, v in pairs(M.user_config) do
      if k == "template_rules" or k == "include_rules" then
        new_config[k] = merge_rules_by_name(new_config[k], v)
      elseif k == "folder_rules" then
        new_config[k] = v
      else
        new_config[k] = deep_merge_tables(new_config[k], v) -- Use deep_merge for other keys
      end
    end
  end

  -- Merge project-specific .ucmrc config
  local project_conf, err = load_project_config(root_dir)
  if not err and project_conf then
    for k, v in pairs(project_conf) do
      if k == "template_rules" or k == "include_rules" then
        new_config[k] = merge_rules_by_name(new_config[k], v)
      elseif k == "folder_rules" then
        new_config[k] = v
      else
        new_config[k] = deep_merge_tables(new_config[k], v) -- Use deep_merge for other keys
      end
    end
  end

  M.active_config = new_config
end

function M.setup(opts)
  M.user_config = opts or {}
  M.load_config(vim.fn.getcwd())
end

-- Initial load of configuration when the module is first required.
M.setup({})

return M
