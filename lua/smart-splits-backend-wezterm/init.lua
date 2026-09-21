---@module 'smart-splits.backend'

local config = require('smart-splits-backend-wezterm.config')
local health = require('smart-splits-backend-wezterm.health')
local move = require('smart-splits-backend-wezterm.move')
local resize = require('smart-splits-backend-wezterm.resize')
local userscript = require('smart-splits-backend-wezterm.userscript')

---@return boolean
local function in_wezterm_pane()
  return vim.env.WEZTERM_PANE ~= nil and #vim.env.WEZTERM_PANE > 0
end

---Set by the GUI plugin's `apply_to_config`, via `config.set_environment_variables`. Its presence
---means the whole integration is wired up, not just that a `wezterm` binary exists somewhere: with
---no plugin listening, a `move()`/`resize()` user-var write always "succeeds" and nothing happens,
---so this handshake is what keeps `detect()` honest instead of an `executable()` check.
---@return boolean
local function gui_plugin_loaded()
  return vim.env.SMART_SPLITS_WEZTERM ~= nil
end

---@type SmartSplitsBackend
local M = {
  name = 'smart-splits-backend-wezterm',
  protocol_version = '3.0.0',
  setup = function(opts)
    config.setup(opts)
  end,
  detect = function()
    return in_wezterm_pane() and gui_plugin_loaded()
  end,
  move = move.move,
  resize = resize.resize,
  health = health.report,
}

---Called once, when this backend wins resolution. Publishes `IS_NVIM` so the GUI plugin's
---keybindings know whether to forward a chord into this pane or act on it themselves, and keeps
---it cleared while Neovim isn't actually running here.
function M.activate()
  userscript.write_user_var('IS_NVIM', 'true')
  local group = vim.api.nvim_create_augroup('smart_splits_backend_wezterm', { clear = true })
  vim.api.nvim_create_autocmd({ 'VimSuspend', 'VimLeavePre' }, {
    group = group,
    callback = function()
      userscript.write_user_var('IS_NVIM', 'false')
    end,
  })
  vim.api.nvim_create_autocmd('VimResume', {
    group = group,
    callback = function()
      userscript.write_user_var('IS_NVIM', 'true')
    end,
  })
end

return M
