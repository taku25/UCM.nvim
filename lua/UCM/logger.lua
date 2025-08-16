-- lua/UCM/logger.lua

-- This module serves as the public interface for logging and messaging.
-- It acts as a facade, delegating calls to the underlying writer implementation.
-- This keeps the API consistent with UBT.nvim for future refactoring.

-- 内部モジュールをrequire
local msg_writer = require("UCM.writer.msg")

-- 公開するAPIを定義
local M = {
  info = msg_writer.info,
  warn = msg_writer.warn,
  error = msg_writer.error,
  -- UBT.nvimに合わせて、より汎用的なlog/write関数も用意しておく
  write = msg_writer.echo, 
}

return M
