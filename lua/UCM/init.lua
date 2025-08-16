-- lua/UCG/init.lua

-- This is the main entry point for the UCG.nvim plugin.
-- It handles the setup process and exposes the public API.

local conf = require("UCM.conf")

-- The main module table that will be returned by `require("UCG")`
local M = {}

--- The main setup function for the plugin.
-- Users will call this from their Neovim config.
-- @param user_opts table|nil User-provided configuration options.
function M.setup(user_opts)
  conf.setup(user_opts)
end


return M
