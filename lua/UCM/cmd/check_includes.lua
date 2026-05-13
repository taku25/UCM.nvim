--- lua/UCM/cmd/check_includes.lua
--- バッファ内の #include 不足を UNL DB で検出し、
--- vim.diagnostic として表示 + :UCM fix_includes で自動挿入する

local unl_api = require("UNL.api")
local log     = require("UCM.logger")

local M = {}

local NS = vim.api.nvim_create_namespace("ucm_includes")

-- バッファごとの最後のチェック結果
local last_result = {}  -- [bufnr] = { missing, insert_line }

--- #include 不足をチェックして diagnostic を設定する
function M.check(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    local file_path = vim.api.nvim_buf_get_name(bufnr)
    if file_path == "" then return end

    local ext = file_path:match("%.([^%.]+)$")
    if not ext or not ({ cpp = 1, h = 1, cc = 1, inl = 1 })[ext] then return end

    local lines   = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    unl_api.db.check_includes(file_path, content, function(result, err)
        if err or not result then
            log.get().debug("check_includes error: %s", tostring(err))
            return
        end

        last_result[bufnr] = result

        local diagnostics = {}
        for _, item in ipairs(result.missing or {}) do
            local lnum = math.max(0, (item.line or 1) - 1)  -- 0-based
            table.insert(diagnostics, {
                bufnr     = bufnr,
                lnum      = lnum,
                col       = 0,
                severity  = vim.diagnostic.severity.WARN,
                source    = "UCM",
                message   = ('Missing #include "%s"  (used: %s)'):format(item.header, item.symbol),
                user_data = { header = item.header },
            })
        end

        vim.diagnostic.set(NS, bufnr, diagnostics)

        if #diagnostics > 0 then
            log.get().info("check_includes: %d missing #include(s) in %s",
                #diagnostics, vim.fn.fnamemodify(file_path, ":t"))
        end
    end)
end

--- 不足している #include を一括挿入する (:UCM fix_includes)
function M.fix(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local result = last_result[bufnr]
    if not result or not result.missing or #result.missing == 0 then
        vim.notify("[UCM] No missing includes found. Run :w or :UCM check_includes first.",
            vim.log.levels.INFO)
        return
    end

    -- 重複除去 + ソート
    local seen    = {}
    local headers = {}
    for _, item in ipairs(result.missing) do
        if not seen[item.header] then
            seen[item.header] = true
            table.insert(headers, item.header)
        end
    end
    table.sort(headers)

    -- insert_line は 1-based → nvim_buf_set_lines は 0-based
    local insert_at = math.max(0, (result.insert_line or 1) - 1)

    local new_lines = {}
    for _, h in ipairs(headers) do
        table.insert(new_lines, ('#include "%s"'):format(h))
    end

    vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, new_lines)
    vim.notify(("[UCM] Inserted %d missing include(s)."):format(#new_lines), vim.log.levels.INFO)

    -- 挿入後に再チェック
    M.check(bufnr)
end

--- Autocmd のセットアップ（once）
local setup_done = false
function M.setup_autocmds()
    if setup_done then return end
    setup_done = true

    local group = vim.api.nvim_create_augroup("UCMIncludes", { clear = true })

    vim.api.nvim_create_autocmd("BufWritePost", {
        group   = group,
        pattern = { "*.cpp", "*.h", "*.cc", "*.inl" },
        callback = function(ev) M.check(ev.buf) end,
    })

    vim.api.nvim_create_autocmd("BufReadPost", {
        group   = group,
        pattern = { "*.cpp", "*.h", "*.cc", "*.inl" },
        callback = function(ev)
            -- DB の準備を待ってからチェック
            vim.defer_fn(function() M.check(ev.buf) end, 2000)
        end,
    })

    vim.api.nvim_create_autocmd("BufDelete", {
        group    = group,
        callback = function(ev) last_result[ev.buf] = nil end,
    })
end

return M
