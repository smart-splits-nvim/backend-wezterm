local M = {}

---@param opts? { pane?: string, plugin_version?: string }
function M.set_wezterm_env(opts)
  opts = opts or {}
  local health = require('smart-splits-backend-wezterm.health')
  vim.env.WEZTERM_PANE = opts.pane or '0'
  vim.env.SMART_SPLITS_WEZTERM = opts.plugin_version or health.COMPATIBLE_PLUGIN_VERSION
end

function M.clear_wezterm_env()
  vim.env.WEZTERM_PANE = nil
  vim.env.SMART_SPLITS_WEZTERM = nil
end

---Reset config, the captured-writes fixture, and WezTerm env vars to a known "fully detected"
---state. Call from `before_each`.
function M.reset_backend()
  local capture = require('tests.fixtures.capture_user_vars')
  capture.install()
  capture.reset()

  local config = require('smart-splits-backend-wezterm.config')
  config.setup()

  M.set_wezterm_env()
end

return M
