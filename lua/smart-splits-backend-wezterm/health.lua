local config = require('smart-splits-backend-wezterm.config')

local M = {}

---Kept in sync by hand with `PLUGIN_VERSION` in `plugin/init.lua`; bump both together on release.
---Used only to explain a mismatch in `:checkhealth`, never to gate `detect()`.
M.COMPATIBLE_PLUGIN_VERSION = '0.1.0'

---@return string|nil version
---@return string|nil error
local function wezterm_version()
  local ok, result = pcall(function()
    return vim.system({ config.options.cli_path, '--version' }, { text = true, timeout = 1000 }):wait()
  end)
  if not ok then
    return nil, 'failed to run wezterm --version'
  end
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or '')
  end
  return vim.trim(result.stdout or ''), nil
end

function M.report()
  if vim.env.WEZTERM_PANE ~= nil and #vim.env.WEZTERM_PANE > 0 then
    vim.health.ok('Running inside a WezTerm pane.')
  else
    vim.health.error('Not running inside a WezTerm pane.')
  end

  local plugin_version = vim.env.SMART_SPLITS_WEZTERM
  if plugin_version == nil then
    vim.health.warn(
      'GUI plugin not detected (SMART_SPLITS_WEZTERM unset). '
        .. 'Add `apply_to_config` to your wezterm.lua — see the README. '
        .. 'Until then this backend stays inactive and Neovim-internal movement still works.'
    )
  elseif plugin_version ~= M.COMPATIBLE_PLUGIN_VERSION then
    vim.health.warn(
      string.format(
        'GUI plugin version mismatch: plugin reports %s, this backend expects %s. Update whichever is behind.',
        plugin_version,
        M.COMPATIBLE_PLUGIN_VERSION
      )
    )
  else
    vim.health.ok(string.format('GUI plugin v%s loaded and matches this backend.', plugin_version))
  end

  -- diagnostic only, never gates detect()/move()/resize(): health() is allowed a subprocess,
  -- detect() is not
  local version, err = wezterm_version()
  if version then
    vim.health.info('Found ' .. version)
  else
    vim.health.info('wezterm CLI not runnable (' .. (err or 'unknown error') .. '); harmless, diagnostic only.')
  end
end

function M.check()
  vim.health.start('backend-wezterm')
  M.report()
end

return M
