-- lua/UCM/logic/outline.lua

local cmd_core = require("UCM.cmd.core")
local log = require("UCM.logger")

local M = {}

-- DB から返ってくるフラットな members 配列を
-- build_class_node が期待する {methods, fields} ネスト形式に変換する
local ACCESSES = { "public", "protected", "private" }

local KIND_MAP = {
    UClass  = "UClass",  uclass  = "UClass",
    UStruct = "UStruct", ustruct = "UStruct",
    UEnum   = "UEnum",   uenum   = "UEnum",
    class   = "Class",   struct  = "Struct",
    ["Class"]  = "Class", ["Struct"] = "Struct",
}

local function member_kind(m, class_name)
    local mtype  = m.type  or ""
    local flags  = m.flags or ""
    if mtype == "function" then
        if flags:find("UFUNCTION") then return "UFunction" end
        local n = m.name or ""
        if n == class_name or n == ("~" .. class_name) then return "Constructor" end
        return "Function"
    else
        if flags:find("UPROPERTY") then return "UProperty" end
        return "Field"
    end
end

local function transform_db_symbol(db_sym, fallback_file_path)
    local methods = {}
    local fields  = {}
    for _, a in ipairs(ACCESSES) do methods[a] = {}; fields[a] = {} end

    local cname = db_sym.name or ""
    local sym_file = db_sym.file_path or fallback_file_path or ""

    for _, m in ipairs(db_sym.members or {}) do
        local access = m.access or "public"
        if not methods[access] then methods[access] = {}; fields[access] = {} end

        local kind = member_kind(m, cname)
        local item = {
            name        = m.name,
            line        = m.line,
            kind        = kind,
            detail      = m.detail,
            return_type = m.return_type,
            file_path   = (m.file_path and m.file_path ~= "") and m.file_path or sym_file,
            access      = access,
            is_static   = m.is_static,
        }

        local mtype = m.type or ""
        if mtype == "function" then
            table.insert(methods[access], item)
        else
            table.insert(fields[access], item)
        end
    end

    -- 空の access バケットは除去
    for _, a in ipairs(ACCESSES) do
        if #methods[a] == 0 then methods[a] = nil end
        if #fields[a]  == 0 then fields[a]  = nil end
    end

    local raw_kind = db_sym.kind or db_sym.type or ""
    local class_kind = KIND_MAP[raw_kind] or raw_kind

    return {
        name     = cname,
        kind     = class_kind,
        line     = db_sym.line,
        end_line = db_sym.end_line,
        file_path = sym_file,
        methods  = methods,
        fields   = fields,
    }
end

local function transform_db_symbols(db_symbols, fallback_file_path)
    if type(db_symbols) ~= "table" then return {} end
    local result = {}
    for _, sym in ipairs(db_symbols) do
        table.insert(result, transform_db_symbol(sym, fallback_file_path))
    end
    return result
end

-- ヘルパー: CPPの実装データをヘッダーの定義データにマージする
local function merge_cpp_implementation(header_class, cpp_class_map)
    if not header_class or not cpp_class_map then return end
    
    local cpp_data = cpp_class_map[header_class.name]
    if not cpp_data then return end

    -- methods["impl"] という新しいバケットを作って格納する
    if not header_class.methods["impl"] then header_class.methods["impl"] = {} end

    -- CPP側の全メソッドを "impl" として追加
    -- (public/protected/private の区別はCPP側ではあまり意味がないためフラットに)
    for _, access in ipairs({"public", "protected", "private", "impl"}) do
        if cpp_data.methods[access] then
            for _, method in ipairs(cpp_data.methods[access]) do
                local impl_method = vim.deepcopy(method)
                impl_method.kind = "Implementation" -- UI側での識別用
                table.insert(header_class.methods["impl"], impl_method)
            end
        end
    end
end

---
-- ファイルのシンボル情報をDBから取得して返す
-- .h の場合は .cpp も探して実装情報をマージする
-- @param file_path string
-- @param on_complete function(symbols)
function M.get_outline(file_path, on_complete)
    if not file_path or file_path == "" then
        log.get().error("Outline: get_outline called with empty file_path")
        if on_complete then on_complete({}) end
        return
    end

    local normalized_path = file_path:gsub("\\", "/")
    log.get().debug("Outline: Fetching symbols for normalized path: %s", normalized_path)

    local unl_api = require("UNL.api")
    
    local function fetch_symbols(path, cb)
        if not path or path == "" then
            cb({})
            return
        end
        local p = path:gsub("\\", "/")
        unl_api.db.get_file_symbols(p, function(symbols)
            cb(symbols or {})
        end)
    end

    -- 非同期でペア解決 (RPCを活用)
    cmd_core.resolve_class_pair(normalized_path, function(pair, err)
        local base_path = normalized_path
        local extra_path = nil

        if normalized_path:match("%.cpp$") or normalized_path:match("%.c$") then
            if pair and pair.h then
                base_path = pair.h
                extra_path = normalized_path
            end
        else
            -- .h の場合、ペアの .cpp があればマージ対象にする
            if pair and pair.cpp then
                extra_path = pair.cpp
            end
        end

        log.get().debug("Outline: Base=%s, Extra=%s", base_path, tostring(extra_path))

        fetch_symbols(base_path, function(base_symbols_raw)
            -- DB フォーマット → Lua UI フォーマットに変換
            local base_symbols = transform_db_symbols(base_symbols_raw, base_path)

            if extra_path and vim.fn.filereadable(extra_path) == 1 then
                fetch_symbols(extra_path, function(extra_symbols_raw)
                    local extra_symbols = transform_db_symbols(extra_symbols_raw, extra_path)
                    local extra_class_map = {}
                    for _, s in ipairs(extra_symbols) do
                        extra_class_map[s.name] = s
                    end

                    for _, symbol in ipairs(base_symbols) do
                        local k = symbol.kind or ""
                        if k == "UClass" or k == "Class" or k == "UStruct" or k == "Struct" then
                            merge_cpp_implementation(symbol, extra_class_map)
                        end
                    end
                    on_complete(base_symbols)
                end)
            else
                on_complete(base_symbols)
            end
        end)
    end)
end

return M

