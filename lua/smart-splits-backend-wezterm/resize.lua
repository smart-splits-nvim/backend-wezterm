---@module 'smart-splits.backend'

local userscript = require('smart-splits-backend-wezterm.userscript')

local M = {}

---@param direction SmartSplitsDirection
---@param opts? SmartSplitsBackendResizeOpts
---@return boolean
function M.resize(direction, opts)
  opts = opts or {}
  -- report whether the OSC write itself reached the terminal, same as move() — see its comment
  return userscript.request({ action = 'resize', dir = direction, amount = math.floor(opts.amount or 1) })
end

return M
