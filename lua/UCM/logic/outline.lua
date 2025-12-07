-- lua/UCM/logic/outline.lua
local unl_parser = require("UNL.parser.cpp")
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
-- ファイルのシンボル情報を解析して返す
-- .h の場合は .cpp も探して実装情報をマージする
-- @param file_path string
-- @return table リスト形式のシンボルデータ
function M.get_outline(file_path)
    local pair, _ = cmd_core.resolve_class_pair(file_path)
    
    -- ペアが見つからなければ単体解析
    if not pair then
        log.get().debug("Outline: No pair found for %s, parsing single file.", file_path)
        local result = unl_parser.parse(file_path)
        return result.list or {}
    end

    -- ヘッダーを主として解析
    local header_path = pair.h
    local cpp_path = pair.cpp
    
    -- ヘッダー解析
    local h_result = unl_parser.parse(header_path)
    local symbols = h_result.list or {}

    -- ソースがあれば解析してマージ
    if cpp_path and vim.fn.filereadable(cpp_path) == 1 then
        local cpp_result = unl_parser.parse(cpp_path)
        
        -- ヘッダー内の各クラスに対して、CPP側の実装を紐付ける
        for _, symbol in ipairs(symbols) do
            if symbol.kind == "UClass" or symbol.kind == "Class" or 
               symbol.kind == "UStruct" or symbol.kind == "Struct" then
                merge_cpp_implementation(symbol, cpp_result.map)
            end
        end
    end

    return symbols
end

return M
