---smart-splits WezTerm GUI plugin. Loaded via:
---  local smart_splits = wezterm.plugin.require('https://github.com/smart-splits-nvim/backend-wezterm')
---  smart_splits.apply_to_config(config, opts)
---
---Owns the <C-h/j/k/l>-style keybindings at the terminal-emulator level, decides whether a
---keypress should pass through into a pane running Neovim (the IS_NVIM user-var, written by the
---Neovim-side backend's activate()) or be handled here directly, and performs the actual pane
---navigation/resize/split — including for requests the Neovim side sends when its own window
---layout runs out of room, over the SMART_SPLITS_REQ user-var. See backend-wezterm's README,
---"The command channel", for why this doesn't go through `wezterm cli`.
---
---The pane-navigation decision logic here (do_move/do_wrap/do_split and the user-var-changed
---dispatch) has unit tests under tests/plugin/, run against a fake `wezterm` module — see
---tests/fixtures/fake_wezterm.lua. What those tests cannot cover — real key dispatch, real pane
---geometry, the real OSC 1337 round-trip — still needs the manual checklist in the README before
---tagging a release.

if vim ~= nil then
  return -- this is a Wezterm plugin, not part of the Neovim plugin
end

local wezterm = require('wezterm')

---Locate this plugin_dir and add it to package.path.
---@return table|nil plugin Installed plugin entry.
local function bootstrap()
  -- selene: allow(incorrect_standard_library_use)
  local sep = package.config:sub(1, 1)

  for _, p in ipairs(wezterm.plugin.list()) do
    if p.url:find('backend-wezterm', 1, true) then
      local base = p.plugin_dir .. sep .. 'plugin' .. sep
      local entries = {
        base .. '?.lua',
        base .. '?' .. sep .. 'init.lua',
      }

      for _, entry in ipairs(entries) do
        if not package.path:find(entry, 1, true) then
          package.path = package.path .. ';' .. entry
        end
      end

      return p
    end
  end
end

bootstrap()

local act = wezterm.action

local geometry = require('geometry')

-- Kept in sync by hand with COMPATIBLE_PLUGIN_VERSION in
-- lua/smart-splits-backend-wezterm/health.lua; bump both together on release.
local PLUGIN_VERSION = '0.1.0'

local DIR = { left = 'Left', right = 'Right', up = 'Up', down = 'Down' }
-- direction order used by the flat `direction_keys = {'h','j','k','l'}` shorthand, matching the
-- pre-v3 integration's documented convention
local ORDER = { 'left', 'down', 'up', 'right' }

local LOG_LEVELS = { error = 1, warn = 2, info = 3 }

local DEFAULTS = {
  direction_keys = {
    move = { 'h', 'j', 'k', 'l' },
    resize = { 'h', 'j', 'k', 'l' },
  },
  modifiers = {
    move = 'CTRL',
    resize = 'META',
  },
  -- what to do when moving and there is no pane in that direction: 'stop' passes the keystroke
  -- through to the program in the pane (see is_nvim() below — this only matters for panes not
  -- running Neovim directly, i.e. keypresses dispatched straight from a WezTerm keybinding).
  --
  -- This same config also governs the case where Neovim itself hits its own edge instead —
  -- including the single-pane case, one WezTerm pane internally split by Neovim with no more
  -- Neovim windows to move into — and asks WezTerm to take over via SMART_SPLITS_REQ. Neovim's
  -- request carries no at_edge preference of its own (see move.lua): this WezTerm-side config is
  -- the only place at_edge is decided, for both call sites, so it's the only place a custom
  -- function for open-ended behavior needs to be written.
  at_edge = 'stop',
  -- whether navigation is blocked while the current pane is zoomed in; applies to both a direct
  -- keybinding and a SMART_SPLITS_REQ from Neovim, for the same reason at_edge above does.
  block_nav_on_zoom = false,
  log_level = 'info',
}

local M = {}
M.config = DEFAULTS

---@param direction_keys table|nil either `{move=..., resize=...}` or the flat `{'h','j','k','l'}` shorthand
---@return table|nil
local function normalize_direction_keys(direction_keys)
  if direction_keys == nil then
    return nil
  end
  if direction_keys.move ~= nil or direction_keys.resize ~= nil then
    return direction_keys
  end
  return { move = direction_keys, resize = direction_keys }
end

---True for a plain list (sequential integer keys from 1..n, or empty). merge() replaces these
---wholesale rather than merging index-wise — a user overriding e.g. `direction_keys.move` wants
---their whole list, not a mix of their entries and stock defaults at whatever indices they didn't
---set.
---@param t table
---@return boolean
local function is_list(t)
  return t[1] ~= nil or next(t) == nil
end

---@param defaults any
---@param opts any
local function merge(defaults, opts)
  if type(defaults) ~= 'table' then
    if opts == nil then
      return defaults
    end
    return opts
  end
  if type(opts) == 'table' and is_list(defaults) then
    return opts
  end
  local out = {}
  for k, v in pairs(defaults) do
    -- recurse even with no opts for this key, so nested tables are copied rather than aliased:
    -- config_opts must never share table identity with DEFAULTS, or a future in-place mutation of
    -- a merged sub-table would corrupt the defaults for the rest of this WezTerm process
    out[k] = type(v) == 'table' and merge(v, nil) or v
  end
  if type(opts) == 'table' then
    for k, v in pairs(opts) do
      if type(v) == 'table' and type(out[k]) == 'table' then
        out[k] = merge(out[k], v)
      else
        out[k] = v
      end
    end
  end
  return out
end

-- Shared between apply_to_config's key callbacks and the user-var-changed handler below, since
-- both need at_edge/log_level and both are registered by the same call.
local config_opts = DEFAULTS

---@param level 'error'|'warn'|'info'
local function log(level, fmt, ...)
  if LOG_LEVELS[level] <= (LOG_LEVELS[config_opts.log_level] or LOG_LEVELS.info) then
    local fn = level == 'error' and wezterm.log_error or level == 'warn' and wezterm.log_warn or wezterm.log_info
    fn(fmt:format(...))
  end
end

---@param panes table[] PaneInformation[]
---@param pane_id integer
---@return table|nil
local function find_pane_info(panes, pane_id)
  for _, info in ipairs(panes) do
    if info.pane:pane_id() == pane_id then
      return info
    end
  end
  return nil
end

---@param window any
---@param pane any
---@param direction SmartSplitsDirection
local function do_split(window, pane, direction)
  window:perform_action(act.SplitPane({ direction = DIR[direction] }), pane)
end

---Activate the farthest pane in the opposite direction; call `fallback` (if given) when there's
---none to wrap to — matching the documented behavior ("falls back to `'stop'`... when no other
---pane shares that row/column").
---@param window any
---@param pane any
---@param panes table[] PaneInformation[]
---@param origin table PaneInformation
---@param direction SmartSplitsDirection
---@param fallback fun()|nil
---@return boolean wrapped
local function do_wrap(window, pane, panes, origin, direction, fallback)
  local target = geometry.far_edge_panes(panes, origin, direction)[1]
  if target ~= nil then
    window:perform_action(act.ActivatePaneByIndex(target.index), pane)
    return true
  end
  if fallback then
    fallback()
  end
  return false
end

---The one place pane navigation actually happens — called both from a direct keybinding (pane not
---running Neovim) and from the SMART_SPLITS_REQ handler (Neovim asked, having hit its own edge).
---
---`fallback`, when given, is called whenever WezTerm itself has nothing left to do: no neighbor,
---`at_edge == 'stop'`, or `at_edge == 'wrap'` with no pane to wrap to. The direct-keybinding call
---site passes a closure that sends the real keystroke through to the pane's program — matching the
---documented default ("'stop' passes the keystroke through... since WezTerm is not the program you
---are typing into"). The SMART_SPLITS_REQ handler passes nil: there is no keystroke to forward,
---Neovim already consumed it internally before asking for help.
---
---When `at_edge` is a function, it's called with a context table matching the pre-v3 integration's
---documented shape exactly (`window`, `pane`, `direction` in WezTerm's own casing, `key`, and
---`split()`/`wrap()`/`send_key()` closures) — a config written against the old docs should keep
---working unmodified. `key`/`send_key` only make sense for the direct-keybinding call site (there's
---a real keystroke to name and forward); the SMART_SPLITS_REQ path calls this with `key = nil`, so
---`ctx.key` is nil and `ctx.send_key()` is a no-op there (no fallback to call).
---@param window any
---@param pane any
---@param direction SmartSplitsDirection
---@param fallback fun()|nil
---@param key string|nil the literal key that was pressed, for `ctx.key`; nil from the request handler
local function do_move(window, pane, direction, fallback, key)
  local tab = pane:tab()
  if tab == nil then
    if fallback then
      fallback()
    end
    return
  end
  local panes = tab:panes_with_info()
  local origin = find_pane_info(panes, pane:pane_id())
  if origin == nil then
    if fallback then
      fallback()
    end
    return
  end

  if M.config.block_nav_on_zoom and origin.is_zoomed then
    return -- a hard stop, not a passthrough case: the request explicitly asked to block here
  end

  if geometry.has_neighbor(panes, origin, direction) then
    window:perform_action(act.ActivatePaneDirection(DIR[direction]), pane)
    return
  end

  local at_edge = M.config.at_edge
  if type(at_edge) == 'function' then
    at_edge({
      window = window,
      pane = pane,
      direction = DIR[direction],
      key = key,
      split = function()
        do_split(window, pane, direction)
      end,
      wrap = function()
        do_wrap(window, pane, panes, origin, direction, fallback)
      end,
      send_key = function()
        if fallback then
          fallback()
        end
      end,
    })
    return
  end

  if at_edge == 'split' then
    do_split(window, pane, direction)
    return
  end

  if at_edge == 'wrap' then
    do_wrap(window, pane, panes, origin, direction, fallback) -- calls fallback itself if nothing to wrap to
    return
  end

  if fallback then
    fallback()
  end
end

---@param window any
---@param pane any
---@param direction SmartSplitsDirection
---@param amount number|nil
local function do_resize(window, pane, direction, amount)
  window:perform_action(act.AdjustPaneSize({ DIR[direction], amount or 1 }), pane)
end

wezterm.on('user-var-changed', function(window, pane, name, value)
  if name ~= 'SMART_SPLITS_REQ' then
    return
  end

  local ok, req = pcall(wezterm.json_parse, value)
  if not ok or type(req) ~= 'table' or type(req.dir) ~= 'string' or DIR[req.dir] == nil then
    log('warn', 'smart-splits: malformed SMART_SPLITS_REQ: %s', tostring(value))
    return
  end

  if req.action == 'resize' then
    do_resize(window, pane, req.dir, req.amount)
  else
    -- no fallback, no key: this is Neovim reporting it already hit its own edge, not a raw
    -- keystroke to forward. at_edge/block_nav_on_zoom come from M.config alone here, same as the
    -- direct-keybinding call site below — Neovim's request carries neither.
    do_move(window, pane, req.dir, nil, nil)
  end
end)

---@param pane any
---@return boolean
local function is_nvim(pane)
  return pane:get_user_vars().IS_NVIM == 'true'
end

---@param config any WezTerm config builder
---@param opts table|nil
function M.apply_to_config(config, opts)
  -- shallow copy: never mutate the caller's own table in place (e.g. a shared config module, or
  -- the same table literal reused across more than one apply_to_config call)
  local user_opts = {}
  for k, v in pairs(opts or {}) do
    user_opts[k] = v
  end
  user_opts.direction_keys = normalize_direction_keys(user_opts.direction_keys)
  config_opts = merge(DEFAULTS, user_opts)

  config.set_environment_variables = config.set_environment_variables or {}
  config.set_environment_variables.SMART_SPLITS_WEZTERM = PLUGIN_VERSION

  config.keys = config.keys or {}

  for i, direction in ipairs(ORDER) do
    local move_key = config_opts.direction_keys.move[i]
    table.insert(config.keys, {
      key = move_key,
      mods = config_opts.modifiers.move,
      action = wezterm.action_callback(function(window, pane)
        local function send_key()
          window:perform_action(act.SendKey({ key = move_key, mods = config_opts.modifiers.move }), pane)
        end
        if is_nvim(pane) then
          send_key()
        else
          do_move(window, pane, direction, send_key, move_key)
        end
      end),
    })

    local resize_key = config_opts.direction_keys.resize[i]
    table.insert(config.keys, {
      key = resize_key,
      mods = config_opts.modifiers.resize,
      action = wezterm.action_callback(function(window, pane)
        if is_nvim(pane) then
          window:perform_action(act.SendKey({ key = resize_key, mods = config_opts.modifiers.resize }), pane)
        else
          do_resize(window, pane, direction, 1)
        end
      end),
    })
  end

  M.config = config_opts or {}
  log('info', 'smart-splits WezTerm plugin v%s loaded', PLUGIN_VERSION)
end

return M
