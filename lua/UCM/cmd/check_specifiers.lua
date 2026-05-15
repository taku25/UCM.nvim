--- lua/UCM/cmd/check_specifiers.lua
--- UPROPERTY/UFUNCTION などのマクロ引数内で矛盾するスペシファイアの組み合わせを検出し、
--- vim.diagnostic として報告する。

local M = {}

local NS = vim.api.nvim_create_namespace("ucm_specifier_conflicts")

-- 矛盾ルールテーブル。
-- { set = {A, B, ...} }  → set 内の要素が 2 つ以上同時に使われたらエラー
-- { requires = A, needs = {B, C} } → A があるのに B も C もない場合は警告
local CONFLICT_RULES = {
  -- ── UPROPERTY ─────────────────────────────────────────────────
  -- Edit 可視性 (どれか一つだけ)
  { macro = "UPROPERTY", severity = vim.diagnostic.severity.ERROR,
    set = { "EditAnywhere", "EditDefaultsOnly", "EditInstanceOnly",
            "VisibleAnywhere", "VisibleDefaultsOnly", "VisibleInstanceOnly" },
    msg = "Edit/Visible specifiers are mutually exclusive; only one may be used." },
  -- Blueprint アクセス (ReadOnly と ReadWrite は共存不可)
  { macro = "UPROPERTY", severity = vim.diagnostic.severity.ERROR,
    set = { "BlueprintReadOnly", "BlueprintReadWrite" },
    msg = "'BlueprintReadOnly' and 'BlueprintReadWrite' are mutually exclusive." },

  -- ── UFUNCTION ──────────────────────────────────────────────────
  -- ネットワーク RPC (Server / Client / NetMulticast は排他)
  { macro = "UFUNCTION", severity = vim.diagnostic.severity.ERROR,
    set = { "Server", "Client", "NetMulticast" },
    msg = "RPC specifiers 'Server', 'Client', 'NetMulticast' are mutually exclusive." },
  -- Reliable と Unreliable は排他
  { macro = "UFUNCTION", severity = vim.diagnostic.severity.ERROR,
    set = { "Reliable", "Unreliable" },
    msg = "'Reliable' and 'Unreliable' are mutually exclusive." },
  -- BlueprintPure と BlueprintImplementableEvent / BlueprintNativeEvent は組み合わせ不可
  { macro = "UFUNCTION", severity = vim.diagnostic.severity.WARN,
    set = { "BlueprintPure", "BlueprintImplementableEvent" },
    msg = "'BlueprintPure' cannot be combined with 'BlueprintImplementableEvent'." },
  { macro = "UFUNCTION", severity = vim.diagnostic.severity.WARN,
    set = { "BlueprintPure", "BlueprintNativeEvent" },
    msg = "'BlueprintPure' cannot be combined with 'BlueprintNativeEvent'." },
  -- Reliable/Unreliable は RPC がない場合は意味がない
  { macro = "UFUNCTION", severity = vim.diagnostic.severity.WARN,
    needs_any_of = { "Server", "Client", "NetMulticast" },
    triggers = { "Reliable", "Unreliable" },
    msg = "'Reliable'/'Unreliable' requires a network RPC specifier (Server/Client/NetMulticast)." },
  -- WithValidation は RPC 専用
  { macro = "UFUNCTION", severity = vim.diagnostic.severity.WARN,
    needs_any_of = { "Server", "Client", "NetMulticast" },
    triggers = { "WithValidation" },
    msg = "'WithValidation' is only meaningful with a network RPC specifier (Server/Client/NetMulticast)." },
}

--- 1 行のテキストから "MACRO_NAME(...)" を探し、スペシファイア名リストを返す。
--- meta=(...) の中身は除外する。
--- @param line string
--- @return table  { macro_name=string, specifiers=table<string>, col=number }[]
local function parse_macro_specifiers(line)
  local results = {}
  local macros = { "UPROPERTY", "UFUNCTION", "UCLASS", "USTRUCT", "UENUM", "UINTERFACE" }
  for _, macro in ipairs(macros) do
    local s, e = line:find(macro .. "%s*%(")
    if s then
      -- マクロ引数の部分を取り出す (カッコ対応)
      local depth = 0
      local in_meta = 0 -- meta=(...) の深さ
      local arg_start = e + 1
      local args_raw = ""
      for i = e, #line do
        local ch = line:sub(i, i)
        if ch == "(" then
          depth = depth + 1
          -- "meta=(" を検出
          if line:sub(i - 5, i) == "meta=(" then
            in_meta = depth
          end
        elseif ch == ")" then
          if depth == 1 then
            -- マクロ閉じ
            args_raw = line:sub(arg_start, i - 1)
            break
          end
          if in_meta == depth then in_meta = 0 end
          depth = depth - 1
        end
      end

      -- meta=(...) を除去してからトークン化
      local without_meta = args_raw:gsub("meta%s*=%s*%b()", "")
      local specifiers = {}
      for tok in without_meta:gmatch("[%w_]+") do
        -- 値部分 (="...") は除外
        if not tok:match("^%d") then
          table.insert(specifiers, tok)
        end
      end
      if #specifiers > 0 then
        table.insert(results, {
          macro_name = macro,
          specifiers = specifiers,
          col = s - 1, -- 0-based
        })
      end
    end
  end
  return results
end

--- bufnr のすべての行を走査して矛盾を検出し、vim.diagnostic で設定する。
--- @param bufnr integer
function M.check(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then return end
  local ext = file_path:match("%.([^%.]+)$")
  if not (ext == "h" or ext == "cpp" or ext == "inl") then return end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local diagnostics = {}

  for lnum, line in ipairs(lines) do
    local macros_on_line = parse_macro_specifiers(line)
    for _, entry in ipairs(macros_on_line) do
      local spec_set = {}
      for _, s in ipairs(entry.specifiers) do spec_set[s] = true end

      for _, rule in ipairs(CONFLICT_RULES) do
        if rule.macro ~= entry.macro_name then goto continue_rule end

        -- 排他ルール: set 内で 2 つ以上マッチ
        if rule.set then
          local found = {}
          for _, s in ipairs(rule.set) do
            if spec_set[s] then table.insert(found, s) end
          end
          if #found >= 2 then
            table.insert(diagnostics, {
              bufnr   = bufnr,
              lnum    = lnum - 1,
              col     = entry.col,
              message = rule.msg,
              severity = rule.severity,
              source  = "UCM",
            })
          end
        end

        -- 依存ルール: triggers のどれかがあり、needs_any_of が一つもない
        if rule.triggers and rule.needs_any_of then
          local triggered = false
          for _, t in ipairs(rule.triggers) do
            if spec_set[t] then triggered = true; break end
          end
          if triggered then
            local has_needed = false
            for _, n in ipairs(rule.needs_any_of) do
              if spec_set[n] then has_needed = true; break end
            end
            if not has_needed then
              table.insert(diagnostics, {
                bufnr   = bufnr,
                lnum    = lnum - 1,
                col     = entry.col,
                message = rule.msg,
                severity = rule.severity,
                source  = "UCM",
              })
            end
          end
        end

        ::continue_rule::
      end
    end
  end

  vim.diagnostic.set(NS, bufnr, diagnostics, {})
end

--- autocmd で BufWritePost / BufReadPost に自動チェックを設定する。
function M.setup_autocmds()
  vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
    pattern = { "*.h", "*.cpp", "*.inl" },
    callback = function(ev)
      vim.schedule(function() M.check(ev.buf) end)
    end,
  })
end

return M
