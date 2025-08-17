-- lua/UCMUI/frontend/telescope.lua

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local M = {}

function M.select_parent_class(choices, on_select)
  pickers.new({
    prompt_title = "Select Parent Class",
    finder = finders.new_table({ results = choices }),
    sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
    attach_mappings = function(bufnr, map)
      actions.select_default:replace(function()
        actions.close(bufnr)
        on_select(action_state.get_selected_entry()[1])
      end)
    return true
  end} ):find()
end

function M.select_code_directory(on_select)
  pickers.new({
    prompt_title = "Select Target Source Directory",
    cwd = vim.fn.getcwd(),
    finder = finders.new_oneshot_job(
      { "fd", "--full-path", "Source", "--type", "d" },
      {}
    ),
    sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
    attach_mappings = function(bufnr, map)
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        actions.close(bufnr)
        on_select(sel.value) end)
        return true
      end
    }):find()
end

function M.select_cpp_file(on_select)
  pickers.new({
    prompt_title = "Select C++ File (.h/.cpp)",
    cwd = vim.fn.getcwd(),
    finder = require("telescope.finders").new_oneshot_job(
      { "fd", ".", "--extension", "h", "--extension", "cpp" },
      { entry_maker = function(line) return { value = line, display = line, ordinal = line } end }
    ),
    sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
    attach_mappings = function(bufnr, map)
      require("telescope.actions").select_default:replace(function()
        local sel = require("telescope.actions.state").get_selected_entry()
        require("telescope.actions").close(bufnr)
        on_select(sel.value)
      end)
      return true
    end,
  }):find()
end

return M
