---A fake `wezterm` module, narrow enough to cover exactly what `plugin/init.lua` uses
---(`wezterm.action`, `.action_callback`, `.on`, `.json_parse`, `.json_encode`, `.log_*`), so that
---file can be `require()`d and exercised under busted/nlua by pre-seeding `package.loaded.wezterm`
---with an instance of this before requiring `plugin`. See `tests/plugin/helpers.lua`.
---
---This does not make `plugin/init.lua` "automated-tested" in the sense of running against a real
---WezTerm — it tests the pane-navigation *decision logic* (which action gets performed for a given
---geometry and at_edge/config combination) against a faithful but hand-maintained stand-in. Real
---key dispatch, real pane geometry, and the real OSC round-trip still need the manual checklist in
---the README.
local M = {}

---@return table fake_wezterm a fresh instance — one per test, so handler registrations and logs
---from one test never leak into the next
function M.new()
  local fake = {}
  local handlers = {}
  local logs = {}

  -- plugin/init.lua's bootstrap() calls wezterm.plugin.list() unconditionally at module load to
  -- find its own entry (matched by URL) and add `<plugin_dir>/plugin/?.lua` to package.path — that
  -- path addition is what makes plugin/init.lua's own `require('geometry')` resolve. Fake one
  -- "installed" entry pointing at this repo's root, the way a real WezTerm would report the plugin
  -- it loaded via `wezterm.plugin.require(...)`.
  fake.plugin = {
    list = function()
      return {
        { url = 'https://github.com/smart-splits-nvim/backend-wezterm', plugin_dir = vim.fn.getcwd() },
      }
    end,
  }

  -- `wezterm.action.AnyActionName(arg)` — every real action is a distinct field on `wezterm.action`;
  -- this fakes all of them uniformly and just records what was asked for, since the plugin only
  -- ever inspects an action by handing it back to `window:perform_action()`.
  fake.action = setmetatable({}, {
    __index = function(_, name)
      return function(arg)
        return { name = name, arg = arg }
      end
    end,
  })

  -- identity: tests call the returned "action" directly as a plain function(window, pane)
  function fake.action_callback(fn)
    return fn
  end

  function fake.on(event, handler)
    handlers[event] = handler
  end

  ---Invoke a registered event handler directly, the way real WezTerm would fire it.
  function fake.emit(event, ...)
    assert(handlers[event] ~= nil, 'no handler registered for event: ' .. event)
    return handlers[event](...)
  end

  -- busted runs under nlua, which provides a real `vim.json`, so these are genuine round-trips,
  -- not stubs
  function fake.json_parse(str)
    return vim.json.decode(str)
  end

  function fake.json_encode(tbl)
    return vim.json.encode(tbl)
  end

  fake.logs = logs
  ---Empty the log in place (the table object, not just the `.logs` field — `log_*` closures below
  ---close over `logs` directly, so reassigning `fake.logs` would not affect what they write to).
  function fake.clear_logs()
    for i = #logs, 1, -1 do
      table.remove(logs, i)
    end
  end
  function fake.log_info(msg)
    table.insert(logs, { level = 'info', msg = msg })
  end
  function fake.log_warn(msg)
    table.insert(logs, { level = 'warn', msg = msg })
  end
  function fake.log_error(msg)
    table.insert(logs, { level = 'error', msg = msg })
  end

  return fake
end

return M
