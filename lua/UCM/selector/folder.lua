-- lua/UCM/selector/folder.lua
local path = require("UCM.path")
local fs = require("vim.fs")

local function get_config()
  return require("UNL.config").get("UCM")
end
local M = {}

--- Resolves header/source directories, searching up to the module root.
-- @param target_dir string
-- @return table, table: Lists of resolved header_dirs and source_dirs.
function M.resolve_locations(target_dir)
  local default_list = { fs.normalize(target_dir or "") }
  if not target_dir then
    return default_list, default_list
  end

  local conf = get_config()
  local rules = conf.folder_rules or {}
  local normalized_target = fs.normalize(target_dir)

  local header_candidates = {}
  local source_candidates = {}

  local seen_header = {}
  local seen_source = {}

  for dir in fs.parents(fs.joinpath(normalized_target, "a")) do
    local component = fs.basename(dir)
    for _, rule in ipairs(rules) do
      if component:match(rule.regex) then
        -- 現在のターゲットディレクトリから、マッチしたディレクトリ(Public/Private等)までの相対パスを抽出
        local rel_path = normalized_target:sub(#dir + 1)
        -- 置換先のベースディレクトリを作成
        local alternate_base = fs.joinpath(fs.dirname(dir), rule.replacement)
        -- 相対パスを結合して、正しい対となるディレクトリを特定
        local alternate_path = fs.normalize(fs.joinpath(alternate_base, rel_path))

        if vim.fn.isdirectory(alternate_path) == 1 then
          local norm_alt = alternate_path

          -- ★★★ 修正箇所: タイプと格納先リストの関係を正常化 ★★★

          -- type="header" (入力がHeader) -> 出力は Source候補
          if rule.type == "header" then
            if not seen_source[norm_alt] then
              table.insert(source_candidates, norm_alt)
              seen_source[norm_alt] = true
            end
            -- 入力自体はHeader候補として保持
            if not seen_header[normalized_target] then
              table.insert(header_candidates, normalized_target)
              seen_header[normalized_target] = true
            end

            -- type="source" (入力がSource) -> 出力は Header候補
          elseif rule.type == "source" then
            if not seen_header[norm_alt] then
              table.insert(header_candidates, norm_alt)
              seen_header[norm_alt] = true
            end
            -- 入力自体はSource候補として保持
            if not seen_source[normalized_target] then
              table.insert(source_candidates, normalized_target)
              seen_source[normalized_target] = true
            end
          else
            -- 指定なし
            if not seen_header[norm_alt] then
              table.insert(header_candidates, norm_alt)
            end
            if not seen_source[norm_alt] then
              table.insert(source_candidates, norm_alt)
            end
          end
        end
      end
    end
  end

  if #header_candidates == 0 then
    table.insert(header_candidates, normalized_target)
  end
  if #source_candidates == 0 then
    table.insert(source_candidates, normalized_target)
  end

  return header_candidates, source_candidates
end

return M
