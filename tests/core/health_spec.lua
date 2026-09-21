local h = require('tests.helpers')

describe('health()', function()
  before_each(function()
    h.reset_backend()
  end)

  it('does not error when fully detected', function()
    local backend = require('smart-splits-backend-wezterm')
    assert.is_not_nil(backend.health)
    assert.has_no.errors(function()
      backend.health()
    end)
  end)

  it('does not error when the GUI plugin handshake var is absent', function()
    local backend = require('smart-splits-backend-wezterm')
    vim.env.SMART_SPLITS_WEZTERM = nil
    assert.has_no.errors(function()
      backend.health()
    end)
  end)

  it('does not error when not in a WezTerm pane at all', function()
    local backend = require('smart-splits-backend-wezterm')
    h.clear_wezterm_env()
    assert.has_no.errors(function()
      backend.health()
    end)
  end)

  it('does not error on a plugin version mismatch', function()
    local backend = require('smart-splits-backend-wezterm')
    vim.env.SMART_SPLITS_WEZTERM = '0.0.1-not-a-real-version'
    assert.has_no.errors(function()
      backend.health()
    end)
  end)
end)
