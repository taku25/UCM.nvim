-- lua/UCG/writer/msg.lua

-- This module is the core implementation for message output.
-- It directly wraps `vim.api.nvim_echo` and should be considered
-- an internal module, accessed via the `logger` facade.

local M = {}

function M.echo(msg, hl_group, is_error)
  local message = "[UCG] " .. msg
  local highlight = hl_group or "Normal"
  
  -- ご指定の記法に修正
  vim.api.nvim_echo({{ message, highlight }}, true, { err = is_error or false })
end

function M.info(msg)
  M.echo(msg, "Normal", false)
end

function M.warn(msg)
  M.echo("WARNING: " .. msg, "WarningMsg", false)
end

function M.error(msg)
  M.echo("ERROR: " .. msg, "ErrorMsg", true)
end

return M
