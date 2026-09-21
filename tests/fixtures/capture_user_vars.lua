---Test double for `smart-splits-backend-wezterm.userscript`: replaces the module's `_write` seam
---with a collector, so specs assert on what the backend actually sent — the real transport, not a
---mock of a subprocess that no longer exists. See PROTOCOL.md's testing section and the
---"Testing strategy" section of the backend-wezterm implementation spec for why this replaced the
---template's `mock_mux.lua`.
local M = {}

---@type string[]
local writes = {}

local prefix = '\027]1337;SetUserVar='
local suffix = '\007'

---Install the collector in place of the real `_write`. Safe to call repeatedly.
function M.install()
  local userscript = require('smart-splits-backend-wezterm.userscript')
  userscript._write = function(seq)
    table.insert(writes, seq)
    return true
  end
end

---Discard everything captured so far. Does not reinstall the collector.
function M.reset()
  writes = {}
end

---@return string[]
function M.writes()
  return writes
end

---@return integer
function M.count()
  return #writes
end

---Decode a captured OSC 1337 SetUserVar sequence back into its name and (already base64-decoded)
---value. Errors loudly on anything that isn't a well-formed SetUserVar sequence, since a malformed
---escape is exactly the kind of bug this test seam exists to catch.
---@param i integer 1-based index into the captured writes, most recent test usually wants the last one
---@return string name
---@return string value
function M.decode(i)
  local seq = writes[i]
  assert(seq ~= nil, ('no write captured at index %d (only %d captured)'):format(i, #writes))
  assert(seq:sub(1, #prefix) == prefix, 'captured sequence is not a SetUserVar escape: ' .. vim.inspect(seq))
  assert(seq:sub(-#suffix) == suffix, 'captured sequence is missing its BEL terminator: ' .. vim.inspect(seq))

  local body = seq:sub(#prefix + 1, #seq - #suffix)
  local name, b64 = body:match('^([^=]+)=(.+)$')
  assert(name ~= nil, 'captured sequence body has no NAME=VALUE: ' .. vim.inspect(body))

  return name, vim.base64.decode(b64)
end

---Decode the most recently captured write.
---@return string name
---@return string value
function M.decode_last()
  return M.decode(#writes)
end

return M
