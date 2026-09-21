local fake_pane = require('tests.fixtures.fake_pane')
local h = require('tests.plugin.helpers')

---Build a row of panes at the given `left` offsets, all sharing one tab, and return the
---PaneInformation for `origin_id`.
---@param lefts integer[]
---@param origin_id integer
local function row(lefts, origin_id)
  local infos = {}
  for i, left in ipairs(lefts) do
    infos[i] = fake_pane.make_pane_info({ id = i, left = left, width = 80, top = 0, height = 24 })
  end
  fake_pane.make_tab(infos)
  for _, info in ipairs(infos) do
    if info.pane:pane_id() == origin_id then
      return info, infos
    end
  end
  error('origin_id not found')
end

describe('plugin/init.lua move dispatch', function()
  local plugin, fake_wezterm

  before_each(function()
    plugin, fake_wezterm = h.load_plugin()
  end)

  it('sends the neighbor directly when one exists, ignoring at_edge entirely', function()
    local origin = row({ 0, 80 }, 1)
    local config = {}
    plugin.apply_to_config(config, {
      at_edge = function()
        error('at_edge should not be consulted when a neighbor exists')
      end,
    })
    local window, actions = fake_pane.make_window()

    h.find_key_action(config, 'l', 'CTRL')(window, origin.pane) -- move right

    assert.are.equal(1, #actions)
    assert.are.equal('ActivatePaneDirection', actions[1].action.name)
    assert.are.equal('Right', actions[1].action.arg)
  end)

  it('at_edge=stop (default) sends the real keystroke through when there is no neighbor', function()
    local origin = row({ 0, 80 }, 1) -- origin is the leftmost pane: nothing further left
    local config = {}
    plugin.apply_to_config(config, {})
    local window, actions = fake_pane.make_window()

    h.find_key_action(config, 'h', 'CTRL')(window, origin.pane) -- move left

    assert.are.equal(1, #actions)
    assert.are.equal('SendKey', actions[1].action.name)
    assert.are.equal('h', actions[1].action.arg.key)
    assert.are.equal('CTRL', actions[1].action.arg.mods)
  end)

  it("at_edge='split' splits when there is no neighbor", function()
    local origin = row({ 0, 80 }, 1)
    local config = {}
    plugin.apply_to_config(config, { at_edge = 'split' })
    local window, actions = fake_pane.make_window()

    h.find_key_action(config, 'h', 'CTRL')(window, origin.pane)

    assert.are.equal(1, #actions)
    assert.are.equal('SplitPane', actions[1].action.name)
    assert.are.equal('Left', actions[1].action.arg.direction)
  end)

  it("at_edge='wrap' activates the farthest pane on the opposite edge", function()
    local origin = row({ 0, 80, 160 }, 1) -- origin leftmost; farthest-right pane is id 3
    local config = {}
    plugin.apply_to_config(config, { at_edge = 'wrap' })
    local window, actions = fake_pane.make_window()

    h.find_key_action(config, 'h', 'CTRL')(window, origin.pane)

    assert.are.equal(1, #actions)
    assert.are.equal('ActivatePaneByIndex', actions[1].action.name)
    assert.are.equal(3, actions[1].action.arg)
  end)

  it("at_edge='wrap' falls back to sending the keystroke when alone in the tab", function()
    local origin = row({ 0 }, 1)
    local config = {}
    plugin.apply_to_config(config, { at_edge = 'wrap' })
    local window, actions = fake_pane.make_window()

    h.find_key_action(config, 'h', 'CTRL')(window, origin.pane)

    assert.are.equal(1, #actions)
    assert.are.equal('SendKey', actions[1].action.name)
  end)

  describe('at_edge as a function', function()
    it('receives a ctx matching the pre-v3 documented shape', function()
      local origin = row({ 0, 80 }, 1)
      local captured
      local config = {}
      plugin.apply_to_config(config, {
        at_edge = function(ctx)
          captured = ctx
        end,
      })
      local window, actions = fake_pane.make_window()

      h.find_key_action(config, 'h', 'CTRL')(window, origin.pane)

      assert.is_not_nil(captured)
      assert.are.equal(window, captured.window)
      assert.are.equal(origin.pane, captured.pane)
      assert.are.equal('Left', captured.direction) -- WezTerm's own casing, not smart-splits' 'left'
      assert.are.equal('h', captured.key)
      assert.are.equal('function', type(captured.split))
      assert.are.equal('function', type(captured.wrap))
      assert.are.equal('function', type(captured.send_key))
      assert.are.equal(0, #actions) -- the ctx alone performs nothing until called
    end)

    it('ctx.split() splits the pane', function()
      local origin = row({ 0, 80 }, 1)
      local config = {}
      plugin.apply_to_config(config, {
        at_edge = function(ctx)
          ctx.split()
        end,
      })
      local window, actions = fake_pane.make_window()

      h.find_key_action(config, 'h', 'CTRL')(window, origin.pane)

      assert.are.equal(1, #actions)
      assert.are.equal('SplitPane', actions[1].action.name)
      assert.are.equal('Left', actions[1].action.arg.direction)
    end)

    it('ctx.wrap() activates the farthest pane when one exists', function()
      local origin = row({ 0, 80, 160 }, 1)
      local config = {}
      plugin.apply_to_config(config, {
        at_edge = function(ctx)
          ctx.wrap()
        end,
      })
      local window, actions = fake_pane.make_window()

      h.find_key_action(config, 'h', 'CTRL')(window, origin.pane)

      assert.are.equal(1, #actions)
      assert.are.equal('ActivatePaneByIndex', actions[1].action.name)
      assert.are.equal(3, actions[1].action.arg)
    end)

    it('ctx.send_key() sends the real keystroke through', function()
      local origin = row({ 0, 80 }, 1)
      local config = {}
      plugin.apply_to_config(config, {
        at_edge = function(ctx)
          ctx.send_key()
        end,
      })
      local window, actions = fake_pane.make_window()

      h.find_key_action(config, 'h', 'CTRL')(window, origin.pane)

      assert.are.equal(1, #actions)
      assert.are.equal('SendKey', actions[1].action.name)
      assert.are.equal('h', actions[1].action.arg.key)
    end)
  end)

  it('always forwards the raw key when the pane is running Neovim, ignoring at_edge/geometry', function()
    local origin, infos = row({ 0, 80 }, 1)
    infos[1].pane.get_user_vars = function()
      return { IS_NVIM = 'true' }
    end
    local config = {}
    plugin.apply_to_config(config, {
      at_edge = function()
        error('at_edge must not run for a pane running Neovim')
      end,
    })
    local window, actions = fake_pane.make_window()

    h.find_key_action(config, 'h', 'CTRL')(window, origin.pane)

    assert.are.equal(1, #actions)
    assert.are.equal('SendKey', actions[1].action.name)
  end)

  it('block_nav_on_zoom blocks a direct keypress when the pane is zoomed, even with a neighbor', function()
    local infos = {
      fake_pane.make_pane_info({ id = 1, left = 0, is_zoomed = true }),
      fake_pane.make_pane_info({ id = 2, left = 80 }),
    }
    fake_pane.make_tab(infos)
    local config = {}
    plugin.apply_to_config(config, { block_nav_on_zoom = true })
    local window, actions = fake_pane.make_window()

    h.find_key_action(config, 'l', 'CTRL')(window, infos[1].pane) -- move right

    assert.are.equal(0, #actions) -- a hard stop, not a passthrough: no SendKey either
  end)

  it('block_nav_on_zoom=false (default) allows navigation out of a zoomed pane', function()
    local infos = {
      fake_pane.make_pane_info({ id = 1, left = 0, is_zoomed = true }),
      fake_pane.make_pane_info({ id = 2, left = 80 }),
    }
    fake_pane.make_tab(infos)
    local config = {}
    plugin.apply_to_config(config, {})
    local window, actions = fake_pane.make_window()

    h.find_key_action(config, 'l', 'CTRL')(window, infos[1].pane) -- move right

    assert.are.equal(1, #actions)
    assert.are.equal('ActivatePaneDirection', actions[1].action.name)
  end)

  it('publishes the SMART_SPLITS_WEZTERM handshake var', function()
    local config = {}
    plugin.apply_to_config(config, {})
    assert.is_not_nil(config.set_environment_variables)
    assert.is_string(config.set_environment_variables.SMART_SPLITS_WEZTERM)
    assert.is_true(#config.set_environment_variables.SMART_SPLITS_WEZTERM > 0)
  end)
end)

describe('plugin/init.lua user-var-changed handler (SMART_SPLITS_REQ)', function()
  local plugin, fake_wezterm

  before_each(function()
    -- the user-var-changed handler registers itself at module load time (h.load_plugin), not
    -- inside apply_to_config; calling it here just pins config_opts (log_level, etc.) to defaults
    plugin, fake_wezterm = h.load_plugin()
    plugin.apply_to_config({}, {})
    fake_wezterm.clear_logs() -- apply_to_config itself logs an info line; start each test clean
  end)

  it('performs a resize request', function()
    local origin = row({ 0, 80 }, 1)
    local window, actions = fake_pane.make_window()
    local payload = vim.json.encode({ action = 'resize', dir = 'right', amount = 5 })

    fake_wezterm.emit('user-var-changed', window, origin.pane, 'SMART_SPLITS_REQ', payload)

    assert.are.equal(1, #actions)
    assert.are.equal('AdjustPaneSize', actions[1].action.name)
    assert.are.same({ 'Right', 5 }, actions[1].action.arg)
  end)

  it('performs a move request honoring the WezTerm-side at_edge config, no key/fallback available', function()
    local origin = row({ 0, 80 }, 1) -- origin leftmost, moving left has no neighbor
    plugin.apply_to_config({}, { at_edge = 'split' })
    local window, actions = fake_pane.make_window()
    local payload = vim.json.encode({ action = 'move', dir = 'left' })

    fake_wezterm.emit('user-var-changed', window, origin.pane, 'SMART_SPLITS_REQ', payload)

    assert.are.equal(1, #actions)
    assert.are.equal('SplitPane', actions[1].action.name)
  end)

  it('block_nav_on_zoom blocks a move request when the origin pane is zoomed', function()
    local infos = {
      fake_pane.make_pane_info({ id = 1, left = 0, is_zoomed = true }),
      fake_pane.make_pane_info({ id = 2, left = 80 }),
    }
    fake_pane.make_tab(infos)
    plugin.apply_to_config({}, { block_nav_on_zoom = true })
    local window, actions = fake_pane.make_window()
    local payload = vim.json.encode({ action = 'move', dir = 'right' })

    fake_wezterm.emit('user-var-changed', window, infos[1].pane, 'SMART_SPLITS_REQ', payload)

    assert.are.equal(0, #actions)
  end)

  it('ignores at_edge/block_nav_on_zoom in the payload even if a stale client sends them', function()
    local origin = row({ 0, 80 }, 1) -- origin leftmost, moving left has no neighbor
    local window, actions = fake_pane.make_window() -- default config: at_edge = 'stop'
    local payload = vim.json.encode({ action = 'move', dir = 'left', at_edge = 'split', block_nav_when_zoomed = true })

    fake_wezterm.emit('user-var-changed', window, origin.pane, 'SMART_SPLITS_REQ', payload)

    assert.are.equal(0, #actions) -- 'stop' with no fallback: nothing happens
  end)

  it('does nothing and warns on a malformed payload', function()
    local origin = row({ 0, 80 }, 1)
    local window, actions = fake_pane.make_window()

    fake_wezterm.emit('user-var-changed', window, origin.pane, 'SMART_SPLITS_REQ', 'not json')

    assert.are.equal(0, #actions)
    assert.are.equal(1, #fake_wezterm.logs)
    assert.are.equal('warn', fake_wezterm.logs[1].level)
  end)

  it('ignores user-vars that are not SMART_SPLITS_REQ', function()
    local origin = row({ 0, 80 }, 1)
    local window, actions = fake_pane.make_window()

    fake_wezterm.emit('user-var-changed', window, origin.pane, 'IS_NVIM', 'true')

    assert.are.equal(0, #actions)
    assert.are.equal(0, #fake_wezterm.logs)
  end)
end)
