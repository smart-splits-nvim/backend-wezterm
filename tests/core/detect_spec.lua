local h = require('tests.helpers')

describe('detect()', function()
  before_each(function()
    h.reset_backend()
  end)

  it('returns true when in a WezTerm pane and the GUI plugin handshake is present', function()
    local backend = require('smart-splits-backend-wezterm')
    assert.is_true(backend.detect())
  end)

  it('returns false when not running inside a WezTerm pane', function()
    local backend = require('smart-splits-backend-wezterm')
    vim.env.WEZTERM_PANE = nil
    assert.is_false(backend.detect())
  end)

  it('returns false when the GUI plugin handshake var is absent', function()
    local backend = require('smart-splits-backend-wezterm')
    vim.env.SMART_SPLITS_WEZTERM = nil
    assert.is_false(backend.detect())
  end)

  it('returns false when neither is present', function()
    local backend = require('smart-splits-backend-wezterm')
    h.clear_wezterm_env()
    assert.is_false(backend.detect())
  end)
end)
