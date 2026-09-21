# Contributing

Thank you for your interest in contributing to backend-wezterm!

## Development Setup

### Prerequisites (Preferred: Nix + direnv)

If you have Nix and direnv installed:

```sh
direnv allow
```

That's it! All dependencies are provided by the Nix flake.

### Prerequisites (Alternative: Manual Installation)

If you prefer to install tools manually:

```sh
# macOS
brew install neovim stylua lua-language-server luajit luarocks just \
  yamlfmt prettier tombi nixfmt actionlint statix

LUAJIT_PREFIX="$(brew --prefix luajit)"
ROCKS=(--lua-version=5.1 --lua-dir="$LUAJIT_PREFIX" --local)
luarocks "${ROCKS[@]}" install busted 2.3.0
luarocks "${ROCKS[@]}" install nlua 0.3.2
eval "$(luarocks "${ROCKS[@]}" path --bin)"
```

### Running Tests

Run all checks before submitting a PR:

```sh
just check
```

This runs:
- Formatting checks (Stylua, yamlfmt, prettier, tombi, actionlint, statix)
- Selene linting
- LuaLS type checking
- Busted test suite

Individual commands:

```sh
just test        # Run tests
just lint        # Run linters
just fmt-check   # Check formatting
just fmt         # Auto-format code
just typecheck   # Type checking
```

To run the tests against Neovim nightly:

```sh
nix develop .#ci-nightly --command just test
```

The nightly build is downloaded from the [nix-community binary cache](https://nix-community.org/cache/); without that
cache configured, Nix compiles Neovim from source. CI runs `nix flake update neovim-nightly-overlay` first to test the
latest nightly.

## Implementation Guidelines

### Backend Protocol

Your backend must implement the v3 protocol:

```lua
---@class SmartSplitsBackend
---@field name string
---@field protocol_version string  -- "3.0.0"
---@field detect fun():boolean
---@field move SmartSplitsBackendMove
---@field resize? SmartSplitsBackendResize
---@field health? fun()
```

### Type Annotations

Use LuaCATS type annotations extensively. All functions should have:
- Parameter types with `@param`
- Return types with `@return`
- Class definitions with `@class` and `@field`

Example:

```lua
---@param direction SmartSplitsDirection
---@param opts? SmartSplitsBackendMoveOpts
---@return boolean
function M.move(direction, opts)
  -- implementation
end
```

### Testing

All new functionality in `lua/smart-splits-backend-wezterm/` should include tests. The test suite
uses:
- Busted test framework
- nlua (Neovim Lua interpreter)
- smart-splits core's `protocol_tests` for conformance
- `tests/fixtures/capture_user_vars.lua`, which replaces `userscript._write` with a collector so
  specs assert on the actual OSC 1337 sequences the backend writes, instead of mocking a subprocess

Test files follow the pattern `tests/core/*_spec.lua`.

**`plugin/` runs inside WezTerm's own Lua runtime**, which `busted`/`nlua` can't reach directly —
but its pane-navigation decision logic (`do_move`/`do_wrap`/`do_split`, the `user-var-changed`
dispatch, `apply_to_config`'s keybinding wiring) is still tested, against a fake `wezterm` module
(`tests/fixtures/fake_wezterm.lua`, `tests/fixtures/fake_pane.lua`) that's pre-loaded via
`package.loaded.wezterm` before `plugin/init.lua` is `require()`d — see `tests/plugin/helpers.lua`.
Test files follow the pattern `tests/plugin/*_spec.lua`, run by the same `just test`.

What that fake can't cover — real WezTerm key dispatch, real pane objects, the real OSC 1337
round-trip — still needs a real WezTerm. Changes to `plugin/init.lua` or `plugin/geometry.lua`
should add a `tests/plugin/` spec where the logic can be expressed against the fake, *and* be
verified by hand for anything it can't: walk the checklist in
[README.md](./README.md#release-checklist) and say what you tested in your PR description.

## Code Style

- Use 2-space indentation
- Single quotes for strings
- Maximum line length: 120 characters
- Sort requires alphabetically

These are enforced by Stylua, yamlfmt, prettier, tombi, actionlint, and statix.

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `just check` to ensure all checks pass
5. Submit a pull request

## Questions?

Open an issue if you have questions about implementing a backend.
