-- lua/UCMUI/frontend/fzf_lua.lua

local has_fzf, fzf_lua = pcall(require, "fzf-lua")

if not has_fzf then
  return {}
end

local M = {}

---
-- Uses fzf-lua's fzf_exec for generic list selection.
function M.select_parent_class(choices, on_select)
  fzf_lua.fzf_exec(choices, {
    prompt = "Parent Class> ",
    actions = {
      ["enter"] = function(selected)
        vim.schedule(function()
          on_select(selected and #selected > 0 and selected[1] or nil)
        end)
      end,
   },
  })
end

---
-- Uses fzf-lua's fzf_exec with a command for directory finding.
function M.select_code_directory(on_select)
  local find_cmd = "fd --full-path Source --type d"

  fzf_lua.fzf_exec(find_cmd, {
    prompt = "Target Directory> ",
    actions = {
      ["enter"] = function(selected)
        vim.schedule(function()
          on_select(selected and #selected > 0 and selected[1] or nil)
        end)
      end,
    },
  })
end

function M.select_cpp_file(on_select)
  local find_cmd = "fd . --extension h --extension cpp"
  require("fzf-lua").fzf_exec(find_cmd, {
    prompt = "C++ File (.h/.cpp)> ",
    actions = {
      ["enter"] = function(selected)
        vim.schedule(function()
          on_select(selected and #selected > 0 and selected[1] or nil)
        end)
      end,
    },
  })
end

return M
