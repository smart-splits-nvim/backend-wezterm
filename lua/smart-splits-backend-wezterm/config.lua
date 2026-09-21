---@class WeztermBackend.Config
---@field cli_path string name/path of the `wezterm` binary; used only by `health()`'s version probe

---@alias WeztermBackend.PartialConfig { cli_path?: string }

local M = {}

---@type WeztermBackend.Config
M.defaults = {
  cli_path = 'wezterm',
}

---@type WeztermBackend.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? WeztermBackend.PartialConfig
---@return WeztermBackend.Config
function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend('force', M.defaults, opts)
  return M.options
end

return M
