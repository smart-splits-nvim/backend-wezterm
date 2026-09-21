# backend-wezterm

> [!WARNING]
> This is under active development and highly unstable. Breaking changes will occur without warning.

WezTerm integration for [smart-splits.nvim](https://github.com/smart-splits-nvim/smart-splits.nvim) (`v3`).

## About

This repo ships two things, installed separately, that together restore the pre-v3
`<C-h/j/k/l>`-crosses-the-pane-boundary experience:

1. **A Neovim plugin** (`lua/smart-splits-backend-wezterm/`) implementing the smart-splits.nvim v3
   backend protocol. Installed like any other Neovim plugin.
2. **A WezTerm GUI plugin** (`plugin/`) that owns the navigation/resize keybindings inside WezTerm
   itself, and decides whether a keypress should be forwarded into a pane running Neovim or handled
   as a pane action directly. Installed via WezTerm's own `wezterm.plugin.require()`.

Both are required for full navigation. With only the Neovim half installed, `:checkhealth
smart-splits` explains what's missing rather than silently doing nothing — see
[How it works](#how-it-works).

## Install

### 1. Neovim plugin (lazy.nvim)

```lua
{
  "smart-splits-nvim/smart-splits.nvim",
  branch = "v3",
  opts = {
    mux = {
      backend = "smart-splits-backend-wezterm",
    },
  },
  dependencies = {
    {
      "smart-splits-nvim/backend-wezterm",
      opts = {
        -- name/path of the wezterm binary; used only by :checkhealth's diagnostic version probe,
        -- never on any hot path (see "How it works")
        cli_path = 'wezterm',
      },
    },
  },
}
```

### 2. WezTerm plugin

In your `wezterm.lua`:

```lua
local wezterm = require('wezterm')
local smart_splits = wezterm.plugin.require('https://github.com/smart-splits-nvim/backend-wezterm')
local config = wezterm.config_builder()
-- the rest of your WezTerm config

smart_splits.apply_to_config(config, {
  -- the default config is shown here; omit the table entirely to use it as-is

  -- directional keys, in order of: left, down, up, right
  direction_keys = { 'h', 'j', 'k', 'l' },
  -- move/resize can also be configured separately, e.g.:
  --   direction_keys = {
  --     move = { 'h', 'j', 'k', 'l' },
  --     resize = { 'LeftArrow', 'DownArrow', 'UpArrow', 'RightArrow' },
  --   },

  modifiers = {
    move = 'CTRL', -- e.g. CTRL+h to move left
    resize = 'META', -- e.g. META+h to resize left
  },

  -- what happens when there's no WezTerm pane in that direction: both a *direct* keypress in a
  -- pane not running Neovim, and a request from Neovim reporting it hit its own edge, resolve
  -- through this same option — smart-splits.nvim's own `move.at_edge` config has no effect here:
  --   'stop'  -- pass the keystroke through to the program in the pane (default)
  --   'wrap'  -- activate the farthest pane in the opposite direction
  --   'split' -- split the current pane in that direction
  --   function(ctx) ... end -- decide yourself; see below
  at_edge = 'stop',

  -- block navigation (both a direct keypress and a request from Neovim) while the current pane
  -- is zoomed in
  block_nav_on_zoom = false,

  log_level = 'info', -- 'error' | 'warn' | 'info'
})

return config
```

#### `at_edge` as a function

For full control, pass a function instead. It receives a single context table:

```lua
smart_splits.apply_to_config(config, {
  at_edge = function(ctx)
    -- ctx.window    -- the WezTerm GUI window
    -- ctx.pane      -- the active pane, which is at the edge
    -- ctx.direction -- 'Left' | 'Down' | 'Up' | 'Right', in WezTerm's own casing
    -- ctx.key       -- the key that was pressed
    -- ctx.split()   -- split the current pane in ctx.direction
    -- ctx.wrap()    -- activate the farthest pane in the opposite direction,
    --               -- or send the keystroke through if there is none
    -- ctx.send_key() -- pass the keystroke through to the program in the pane

    -- for example, move between tabs at the left and right edges:
    if ctx.direction == 'Left' then
      ctx.window:perform_action(wezterm.action.ActivateTabRelative(-1), ctx.pane)
    elseif ctx.direction == 'Right' then
      ctx.window:perform_action(wezterm.action.ActivateTabRelative(1), ctx.pane)
    else
      ctx.send_key()
    end
  end,
})
```

This also runs for a request from Neovim reporting it hit its own edge, same as `at_edge` as a
string — but there's no keystroke or `ctx.key` to hand you in that case, since Neovim already
consumed it internally and just asked for help. `ctx.key` is `nil` and `ctx.send_key()` is a no-op
when there's nothing to fall back to.

## How it works

Neither half of this integration shells out to `wezterm cli`. Everything goes over WezTerm's user
variables (the same mechanism `SetUserVar`-aware prompts/statuslines use), because the WezTerm
plugin already holds live `window`/`pane`/`tab` objects and can act on them directly — round-tripping
through a CLI subprocess to reach the same mux server would just be slower and less capable
(WezTerm's Lua API exposes pane geometry that its CLI never has).

- **`IS_NVIM`** — written by the Neovim plugin's `activate()`, cleared on `VimSuspend`/`VimLeavePre`,
  set again on `VimResume`. The WezTerm plugin reads it on every keypress to decide: forward the raw
  key into this pane (Neovim will handle it internally), or act on the pane directly.
- **`SMART_SPLITS_REQ`** — written by `move()`/`resize()` when Neovim's own window layout has run out
  of room. A small JSON payload (`{action, dir, amount, ...}`); the WezTerm plugin's
  `user-var-changed` handler performs the actual navigation, resize, or split, deciding `at_edge`/
  `block_nav_on_zoom` purely from its own config (see `at_edge` above) — the payload carries
  neither.
- **`SMART_SPLITS_WEZTERM`** — published by the WezTerm plugin via `config.set_environment_variables`,
  carrying its own version. The Neovim plugin's `detect()` reads it to confirm the WezTerm half is
  actually installed, not just that a `wezterm` binary exists somewhere — since a `SMART_SPLITS_REQ`
  write always "succeeds" whether or not anything is listening, this handshake is what keeps a
  half-installed setup from silently doing nothing. Run `:checkhealth smart-splits` if navigation
  isn't crossing into WezTerm panes — it names exactly what's missing.

## Support matrix

| Requires                                                                  | Minimum WezTerm                                                                               |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `panes_with_info()`, `AdjustPaneSize`, `SplitPane`, `ActivatePaneByIndex` | _to be confirmed against a current WezTerm install; do not assume a version not yet verified_ |

## Release checklist

`just test` covers the Neovim plugin fully, and the WezTerm plugin's pane-navigation decision logic
(which action gets performed for a given geometry/`at_edge`/config combination) against a fake
`wezterm` module — see `tests/fixtures/fake_wezterm.lua`. What that can't cover — real key dispatch,
real WezTerm objects, the real OSC 1337 round-trip — still needs a real WezTerm. Before tagging a
release, walk this by hand and record the version tested against in the release notes:

- [ ] `<C-h/j/k/l>` from inside a Neovim pane passes through and moves the Neovim cursor
- [ ] Moving off Neovim's own edge crosses into the adjacent WezTerm pane
- [ ] Moving back from that pane returns focus to Neovim
- [ ] Setting the WezTerm plugin's `at_edge = 'split'` creates a WezTerm pane in the right direction when Neovim hits its own edge
- [ ] `<C-h/j/k/l>` in a pane that never ran Neovim navigates/splits WezTerm panes directly
- [ ] Quitting Neovim, then pressing the chord in that pane, moves the WezTerm pane (not a passthrough)
- [ ] `:suspend`-ing Neovim behaves the same as quitting, and `:SmartSplitsResize`/movement resumes correctly on return

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).
