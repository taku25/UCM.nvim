-- lua/UCM/config/defaults.lua (UCMのデフォルト設定)
-- UNLのデフォルト設定とマージされます。
local M = {
  logging = {
    level = "info",
    echo = { level = "warn" },
    notify = { level = "error", prefix = "[UCM]" },
    file = { enable = true, max_kb = 512, rotate = 3, filename = "ucm.log" },
    perf = { enabled = false, patterns = { "^refresh" }, level = "trace" },
  },
  cache = { dirname = "UCM" },
  project = {
    localrc_filename = ".ucmrc",
  },


  -- 'new'コマンド成功後、どのファイルを開くか
  -- "header": ヘッダーファイルのみ開く (デフォルト)
  -- "source": ソースファイルのみ開く
  -- "both":   ヘッダーを開き、ソースを縦分割で開く
  -- false:    何もしない
  auto_open_on_new = "header",

  confirm_on_new = true,
  default_parent_class = "Actor",

  copyright_header_h = "// Copyright...",
  copyright_header_cpp = "// Copyright..",

  template_rules = {
    {
      name = "Actor",
      priority = 10,
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

return M
