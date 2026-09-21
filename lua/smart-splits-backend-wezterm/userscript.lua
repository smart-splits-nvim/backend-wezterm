---The whole transport between this backend and the WezTerm-side GUI plugin: an OSC 1337
---`SetUserVar` escape sequence written to the terminal. `IS_NVIM` (state, written by `activate()`)
---and `SMART_SPLITS_REQ` (an event, written by `move()`/`resize()`) both go through this.
local M = {}

---The only place anything leaves the process. Tests replace this field so the rest of the module
---is exercised for real, without needing a real terminal on the other end.
---@param seq string
---@return boolean
M._write = function(seq)
  if vim.fn.filewritable('/dev/fd/2') == 1 then
    return vim.fn.writefile({ seq }, '/dev/fd/2', 'b') == 0
  end
  return vim.fn.chansend(vim.v.stderr, seq) > 0
end

---Write a WezTerm user-var. Building the escape with `string.format` (rather than a literal)
---sidesteps the octal/decimal ambiguity that forced the old integration's `SetUserVar` encoding
---into Vimscript; `vim.base64.encode` needs Neovim >=0.10, already below core's own >=0.11 floor.
---@param name string
---@param value string
---@return boolean
function M.write_user_var(name, value)
  local seq = string.format('\027]1337;SetUserVar=%s=%s\007', name, vim.base64.encode(value))
  return M._write(seq)
end

---Write a `SMART_SPLITS_REQ` user-var for the GUI plugin to act on. `move()`/`resize()` never talk
---to WezTerm directly — see the backend's README, "The command channel", for why.
---@param payload table
---@return boolean wrote whether the OSC escape actually reached the terminal (not whether a GUI
---plugin is listening on the other end — that's unknowable here, see detect())
function M.request(payload)
  return M.write_user_var('SMART_SPLITS_REQ', vim.json.encode(payload))
end

return M
