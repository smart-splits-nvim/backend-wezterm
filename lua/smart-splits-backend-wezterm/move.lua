---@module 'smart-splits.backend'

local userscript = require('smart-splits-backend-wezterm.userscript')

local M = {}

---opts is explicitly not used here as at_edge is handled by the wezterm plugin
---@param direction SmartSplitsDirection
---@param _? SmartSplitsBackendMoveOpts
---@return boolean
function M.move(direction, _)
  return userscript.request({
    action = 'move',
    dir = direction,
  })
end

return M
