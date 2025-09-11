-- lua/UCM/provider/init.lua

local log = require("UNL.logging").get("UCM.nvim")

local M = {}

-- プロバイダーの登録処理
function M.setup()
  -- UNL.provider が利用可能かチェック
  local unl_provider_ok, provider = pcall(require, "UNL.provider")
  if not unl_provider_ok then
    log.warn("UNL.nvim provider system not found. UCM.nvim provider integration is disabled.")
    return
  end

  -- 各capabilityと実装モジュールをテーブルで定義
  local providers_to_register = {
    {
      capability = "ucm.class.new",
      impl = require("UCM.provider.new"),
    },
    {
      capability = "ucm.class.delete",
      impl = require("UCM.provider.delete"),
    },
    {
      capability = "ucm.class.move",
      impl = require("UCM.provider.move"),
    },
    -- ▼▼▼ ここから追加 ▼▼▼
    {
      capability = "ucm.class.rename",
      impl = require("UCM.provider.rename"),
    },
    -- ▲▲▲ ここまで追加 ▲▲▲
  }

  -- ループで一括登録
  for _, spec in ipairs(providers_to_register) do
    provider.register({
      capability = spec.capability,
      name = "UCM.nvim", -- プロバイダー名は共通
      priority = 100,     -- 優先度も共通
      impl = spec.impl,
    })
  end

  log.info("Registered UCM.nvim providers to UNL.nvim for capabilities: ucm.class.*")
end

return M
