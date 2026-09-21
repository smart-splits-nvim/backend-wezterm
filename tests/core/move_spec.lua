local capture = require('tests.fixtures.capture_user_vars')
local h = require('tests.helpers')

describe('move()', function()
  before_each(function()
    h.reset_backend()
  end)

  it('writes a SMART_SPLITS_REQ user-var for a normal move', function()
    local backend = require('smart-splits-backend-wezterm')
    assert.is_true(backend.move('left'))
    assert.are.equal(1, capture.count())

    local name, value = capture.decode_last()
    assert.are.equal('SMART_SPLITS_REQ', name)
    local payload = vim.json.decode(value)
    assert.are.equal('move', payload.action)
    assert.are.equal('left', payload.dir)
  end)

  it('ignores opts — at_edge/block_nav_on_zoom are WezTerm-side-only config now', function()
    local backend = require('smart-splits-backend-wezterm')
    backend.move('right', { at_edge = 'split' })
    local _, value = capture.decode_last()
    local payload = vim.json.decode(value)
    assert.are.equal('right', payload.dir)
    assert.is_nil(payload.at_edge)
    assert.is_nil(payload.block_nav_when_zoomed)
  end)

  it('returns true for every direction when the write succeeds — a send, not a listener check', function()
    local backend = require('smart-splits-backend-wezterm')
    for _, dir in ipairs({ 'left', 'right', 'up', 'down' }) do
      assert.is_true(backend.move(dir))
    end
  end)

  it('returns false when the OSC write itself fails, so core can fall back internally', function()
    local backend = require('smart-splits-backend-wezterm')
    local userscript = require('smart-splits-backend-wezterm.userscript')
    userscript._write = function()
      return false
    end
    assert.is_false(backend.move('left'))
  end)

  it('writes a well-formed escape sequence: ESC, not a literal backslash-033', function()
    local backend = require('smart-splits-backend-wezterm')
    backend.move('left')
    local seq = capture.writes()[capture.count()]
    assert.are.equal('\027', seq:sub(1, 1))
    assert.are.equal(string.byte(seq, 1), 27)
  end)
end)
