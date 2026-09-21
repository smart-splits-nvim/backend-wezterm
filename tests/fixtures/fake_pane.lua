---Builders for fake WezTerm pane/tab/window objects, matching the narrow surface `plugin/init.lua`
---and `plugin/geometry.lua` actually call: `pane:pane_id()`, `pane:tab()`, `pane:get_user_vars()`,
---`tab:panes_with_info()`, `window:perform_action()`. Real `PaneInformation` has many more fields;
---only the geometry ones (`left`/`top`/`width`/`height`/`index`/`is_zoomed`) are faked here.
local M = {}

---@class FakePaneOpts
---@field id integer
---@field index? integer defaults to `id`
---@field left? integer
---@field top? integer
---@field width? integer
---@field height? integer
---@field is_zoomed? boolean
---@field user_vars? table<string, string>

---@param opts FakePaneOpts
---@return table pane_info a PaneInformation-shaped table with a `.pane` object; call `M.make_tab()`
---on a list of these before using `pane:tab()`
function M.make_pane_info(opts)
  local user_vars = opts.user_vars or {}
  local pane = {}
  function pane:pane_id()
    return opts.id
  end
  function pane:get_user_vars()
    return user_vars
  end

  return {
    pane = pane,
    index = opts.index or opts.id,
    left = opts.left or 0,
    top = opts.top or 0,
    width = opts.width or 80,
    height = opts.height or 24,
    is_active = opts.is_active or false,
    is_zoomed = opts.is_zoomed or false,
  }
end

---Wire a list of pane-info tables (from `make_pane_info`) into a tab, and give each pane's `:tab()`
---a way back to it — mirrors real WezTerm, where a pane always knows its containing tab.
---@param pane_infos table[]
---@return table tab
function M.make_tab(pane_infos)
  local tab = {}
  function tab:panes_with_info()
    return pane_infos
  end
  for _, info in ipairs(pane_infos) do
    info.pane.tab = function()
      return tab
    end
  end
  return tab
end

---@return table window
---@return table[] actions every `{action, pane}` the window was asked to perform, in order
function M.make_window()
  local actions = {}
  local window = {}
  function window:perform_action(action, pane)
    table.insert(actions, { action = action, pane = pane })
  end
  return window, actions
end

return M
