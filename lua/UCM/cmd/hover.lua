--- lua/UCM/cmd/hover.lua
--- カーソルが UE マクロ (UPROPERTY/UFUNCTION/UCLASS/USTRUCT/UENUM/UINTERFACE) の
--- スペシファイア上にある場合、そのドキュメントをフローティングウィンドウで表示する。
--- デフォルトは UCMHoverSpecifier コマンド、または K キーで呼び出す。

local M = {}

-- ─── スペシファイア ドキュメント一覧 ──────────────────────────────────────────
-- スペシファイア名 → { summary=string, macro=string|nil }
-- macro が nil の場合は複数マクロで共有
local DOCS = {
  -- ── UPROPERTY ─────────────────────────────────────────────
  EditAnywhere          = { macro="UPROPERTY", summary="Can be edited by property windows in the editor, on instances and archetypes." },
  EditDefaultsOnly      = { macro="UPROPERTY", summary="Can be edited only on archetypes/defaults, not on instances." },
  EditInstanceOnly      = { macro="UPROPERTY", summary="Can be edited only on instances, not on archetypes/defaults." },
  EditFixedSize         = { macro="UPROPERTY", summary="For dynamic arrays: disables adding/removing elements, but allows editing existing elements." },
  VisibleAnywhere       = { macro="UPROPERTY", summary="Visible in all property windows (editor and instances) but not editable." },
  VisibleDefaultsOnly   = { macro="UPROPERTY", summary="Visible on archetypes/defaults, not on instances. Not editable." },
  VisibleInstanceOnly   = { macro="UPROPERTY", summary="Visible on instances, not on archetypes/defaults. Not editable." },
  BlueprintReadOnly     = { macro="UPROPERTY", summary="Can be read from Blueprints but not modified." },
  BlueprintReadWrite    = { macro="UPROPERTY", summary="Can be read and written from Blueprints." },
  BlueprintAssignable   = { macro="UPROPERTY", summary="Multicast delegates only — can be assigned in Blueprints." },
  BlueprintCallable     = nil, -- shared with UFUNCTION (handled below)
  BlueprintAuthorityOnly= nil, -- shared
  Replicated            = { macro="UPROPERTY", summary="This property will be replicated over the network." },
  ReplicatedUsing       = { macro="UPROPERTY", summary="Specifies a callback function called when this property is received via replication." },
  NotReplicated         = { macro="UPROPERTY", summary="Skip replication for this property in struct context. Struct properties are replicated by default." },
  Transient             = { macro="UPROPERTY", summary="Property is not serialized; will be zero-filled at load time." },
  DuplicateTransient    = { macro="UPROPERTY", summary="Property is set to default value during duplication (e.g. copy-paste)." },
  SaveGame              = { macro="UPROPERTY", summary="Include this property when saving a game via checkpoint or serialization." },
  Config                = { macro="UPROPERTY", summary="Value is loaded from the config file (.ini) and saved to it." },
  GlobalConfig          = { macro="UPROPERTY", summary="Works like Config but the value cannot be overridden by subclasses." },
  Instanced             = { macro="UPROPERTY", summary="Object properties only. Allows creating instances of sub-objects in the editor." },
  Export                = { macro="UPROPERTY", summary="Object properties only. Sub-object referenced should be exported as a sub-object block (serialized inline)." },
  NoClear               = { macro="UPROPERTY", summary="Disables the Clear button for object references in the editor." },
  Interp                = { macro="UPROPERTY", summary="Value can be driven over time by a Matinee or Sequencer float track." },
  NonTransactional      = { macro="UPROPERTY", summary="Changes to this property are not included in the editor undo/redo transaction." },
  AdvancedDisplay       = { macro="UPROPERTY", summary="Move this property to the advanced dropdown in the details panel." },
  SimpleDisplay         = { macro="UPROPERTY", summary="Always visible in the details panel (overrides advanced display)." },
  AssetRegistrySearchable = { macro="UPROPERTY", summary="Property and its value are automatically added to the Asset Registry for the containing asset." },
  SkipSerialization     = { macro="UPROPERTY", summary="Property is not serialized but can still be exported." },
  -- ── UFUNCTION ──────────────────────────────────────────────
  BlueprintPure                = { macro="UFUNCTION", summary="Does not affect the owning object in any way; no execution output pin in Blueprints." },
  BlueprintImplementableEvent  = { macro="UFUNCTION", summary="Base implementation is empty; Blueprint subclasses can override it. No C++ body required." },
  BlueprintNativeEvent         = { macro="UFUNCTION", summary="Designed to be overridden by a Blueprint, but has a native (C++) default implementation (_Implementation suffix)." },
  Exec                         = { macro="UFUNCTION", summary="Can be called from in-game console commands." },
  Server                       = { macro="UFUNCTION", summary="Called on the server only. Requires Reliable or Unreliable." },
  Client                       = { macro="UFUNCTION", summary="Called on the owning client. Requires Reliable or Unreliable." },
  NetMulticast                 = { macro="UFUNCTION", summary="Called on the server and all clients. Requires Reliable or Unreliable." },
  Reliable                     = { macro="UFUNCTION", summary="Replicated function call is reliable (guaranteed delivery)." },
  Unreliable                   = { macro="UFUNCTION", summary="Replicated function call may be dropped in bad network conditions." },
  WithValidation               = { macro="UFUNCTION", summary="Declares a separate validation function (_Validate suffix) for network RPC." },
  BlueprintCosmetic            = { macro="UFUNCTION", summary="Only executes in Blueprints on clients (never on dedicated server)." },
  CallInEditor                 = { macro="UFUNCTION", summary="This function can be called from within the editor on selected instances via a button." },
  CustomThunk                  = { macro="UFUNCTION", summary="Allows custom thunk function generation. Used for template functions exposed to Blueprints." },
  SealedEvent                  = { macro="UFUNCTION", summary="This event cannot be overridden in Blueprint subclasses." },
  -- ── UCLASS ─────────────────────────────────────────────────
  Blueprintable           = { macro="UCLASS", summary="This class can be used as a base class for creating Blueprints." },
  NotBlueprintable        = { macro="UCLASS", summary="This class cannot be used as a base class for Blueprints." },
  Abstract                = { macro="UCLASS", summary="Prevents direct instantiation. Must be subclassed." },
  Placeable               = { macro="UCLASS", summary="Can be placed in a level, in the UI Scene, or in a Blueprint." },
  NotPlaceable            = { macro="UCLASS", summary="Cannot be placed in editor views; overrides inherited Placeable." },
  MinimalAPI              = { macro="UCLASS", summary="Only exposes minimal API (faster link times). Does not export all functions." },
  DefaultToInstanced      = { macro="UCLASS", summary="Properties of this class default to instanced." },
  EditInlineNew           = { macro="UCLASS", summary="Can be created inline in property windows." },
  HideDropdown            = { macro="UCLASS", summary="Hide this class from the dropdown menus in the editor." },
  CollapseCategories      = { macro="UCLASS", summary="Properties of this class are collapsed into the parent category in the editor." },
  DontCollapseCategories  = { macro="UCLASS", summary="Prevents inheriting CollapseCategories from a parent class." },
  -- ── USTRUCT ─────────────────────────────────────────────────
  Atomic                  = { macro="USTRUCT", summary="Struct is serialized as a single unit; replicated as a whole." },
  NoExport                = { macro="USTRUCT", summary="Do not export to header tool (intrinsic struct)." },
  -- ── UENUM ──────────────────────────────────────────────────
  -- ── shared ──────────────────────────────────────────────────
  BlueprintType           = { macro=nil,       summary="Can be used as a variable type in Blueprints." },
  Category                = { macro=nil,       summary="Specifies the category in the editor UI / Blueprint action menu." },
  meta                    = { macro=nil,       summary="Additional metadata specifiers for editor and Blueprint tooling." },
}

-- BlueprintCallable と BlueprintAuthorityOnly は共有 (UPROPERTY + UFUNCTION)
DOCS.BlueprintCallable      = { macro=nil, summary="Can be called from Blueprints and other visual scripting." }
DOCS.BlueprintAuthorityOnly = { macro=nil, summary="Only fires in Blueprints running on a machine with network authority." }

-- ─── ヘルパー ────────────────────────────────────────────────────────────────

--- カーソル行のテキストとカーソル列から、カーソルが UE マクロ内にあるかを判定し、
--- マクロ名を返す。なければ nil。
local function detect_macro_at_cursor(line, col)
  local macros = { "UPROPERTY", "UFUNCTION", "UCLASS", "USTRUCT", "UENUM", "UINTERFACE" }
  for _, m in ipairs(macros) do
    local s = line:find(m .. "%s*%(")
    if s then
      -- マクロ開始より後ろにカーソルがあり、閉じカッコより前か？
      local open = line:find("%(", s)
      if open and col >= open then
        -- 閉じカッコを探す (簡易)
        local depth = 0
        for i = open, #line do
          local ch = line:sub(i, i)
          if ch == "(" then depth = depth + 1
          elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then
              if col < i then return m end
              break
            end
          end
        end
        -- 閉じカッコが同一行にない場合もマクロ内と見なす
        if depth > 0 then return m end
      end
    end
  end
  return nil
end

--- フローティングウィンドウでドキュメントを表示する。
--- @param spec_name string
--- @param macro_name string|nil
local function show_float(spec_name, macro_name)
  local entry = DOCS[spec_name]
  if not entry then
    vim.notify(string.format("UCM: no documentation found for '%s'.", spec_name), vim.log.levels.INFO)
    return
  end
  local title = macro_name
      and string.format(" %s  [%s] ", spec_name, macro_name)
      or  string.format(" %s ", spec_name)
  local body = entry.summary or "(no description)"

  local lines = { body }
  local width = math.max(#title + 2, #body + 4, 40)
  width = math.min(width, math.floor(vim.o.columns * 0.7))

  -- 長い行は折り返す
  local wrapped = {}
  for _, l in ipairs(lines) do
    while #l > width - 4 do
      table.insert(wrapped, l:sub(1, width - 4))
      l = l:sub(width - 3)
    end
    table.insert(wrapped, l)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, wrapped)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row      = 1,
    col      = 0,
    width    = width,
    height   = #wrapped,
    style    = "minimal",
    border   = "rounded",
    title    = title,
    title_pos = "center",
  })
  vim.api.nvim_set_option_value("winhl", "Normal:NormalFloat,FloatBorder:FloatBorder", { win = win })

  -- カーソルが動いたら閉じる
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave" }, {
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--- カーソル下のスペシファイアのドキュメントを表示する。
function M.hover()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- カーソル下の単語を取得
  local word_start = col
  while word_start > 0 and line:sub(word_start, word_start):match("[%w_]") do
    word_start = word_start - 1
  end
  local word_end = col + 1
  while word_end <= #line and line:sub(word_end, word_end):match("[%w_]") do
    word_end = word_end + 1
  end
  local word = line:sub(word_start + 1, word_end - 1)
  if word == "" then
    vim.notify("UCM: cursor is not on a word.", vim.log.levels.INFO)
    return
  end

  -- マクロ内かどうか確認
  local macro = detect_macro_at_cursor(line, col + 1)
  show_float(word, macro)
end

return M
