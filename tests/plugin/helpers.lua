local M = {}

---Load a fresh copy of `plugin/init.lua` against a fresh fake `wezterm`. Clears the module cache
---first: the real file has module-level state (the registered `user-var-changed` handler,
---`config_opts` from the last `apply_to_config` call) that must not leak between tests.
---@return table plugin the module returned by plugin/init.lua (i.e. `{apply_to_config = ...}`)
---@return table fake_wezterm this load's fake `wezterm` instance — use `fake_wezterm.emit(...)` to
---fire the registered `user-var-changed` handler, and `fake_wezterm.logs` to inspect log calls
function M.load_plugin()
  package.loaded['plugin'] = nil
  package.loaded['geometry'] = nil

  local fake_wezterm = require('tests.fixtures.fake_wezterm').new()
  package.loaded['wezterm'] = fake_wezterm

  local plugin = require('plugin')
  return plugin, fake_wezterm
end

---Find the `action` callback `apply_to_config` registered for a given `(key, mods)` pair, the way
---WezTerm itself would look it up out of `config.keys` before invoking it.
---@param config table the config table passed to `apply_to_config`
---@param key string
---@param mods string
---@return fun(window: table, pane: table)
function M.find_key_action(config, key, mods)
  for _, entry in ipairs(config.keys) do
    if entry.key == key and entry.mods == mods then
      return entry.action
    end
  end
  error(('no keybinding registered for key=%s mods=%s'):format(key, mods))
end

return M
