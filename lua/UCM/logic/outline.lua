-- lua/UCM/logic/outline.lua

local cmd_core = require("UCM.cmd.core")
local log = require("UCM.logger")

local M = {}

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

        fetch_symbols(base_path, function(base_symbols)
            if extra_path and vim.fn.filereadable(extra_path) == 1 then
                fetch_symbols(extra_path, function(extra_symbols)
                    local extra_class_map = {}
                    for _, s in ipairs(extra_symbols) do
                        extra_class_map[s.name] = s
                    end

                    for _, symbol in ipairs(base_symbols) do
                        if symbol.kind == "UClass" or symbol.kind == "Class" or 
                           symbol.kind == "UStruct" or symbol.kind == "Struct" then
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

