# Smart-splits core revision to test against
SMART_SPLITS_REV := "v3" # TODO: update to v3.0.0 when tagged

# Clone smart-splits core at pinned revision (no-op if already correct)
[private]
deps:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="deps/smart-splits.nvim"
    if [ -d "$dir" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$(git -C "$dir" rev-parse '{{ SMART_SPLITS_REV }}' 2>/dev/null)" ]; then
      exit 0
    fi
    rm -rf "$dir"
    mkdir -p deps
    git clone --filter=blob:none --no-checkout https://github.com/smart-splits-nvim/smart-splits.nvim "$dir"
    git -C "$dir" checkout --quiet '{{ SMART_SPLITS_REV }}'

# Force re-clone smart-splits core
[private]
deps-force:
    rm -rf deps/smart-splits.nvim
    just deps

# Run all tests
# `core` exercises the Neovim-side backend against smart-splits core's protocol_tests. `plugin`
# exercises plugin/'s pane-navigation decision logic against a fake `wezterm` module (see
# tests/fixtures/fake_wezterm.lua) — real key dispatch and real WezTerm objects still need the
# manual checklist in README.md, which this does not replace.
test: deps
    #!/usr/bin/env bash
    set -euo pipefail
    export SMART_SPLITS_DIR="$(pwd)/deps/smart-splits.nvim"
    busted --run=core
    busted --run=plugin

# Check formatting
fmt-check:
    stylua --check lua tests plugin
    yamlfmt -gitignore_excludes -dry .
    prettier --check "**/*.{json,jsonc}"
    tombi format --offline --check .
    nixfmt --check flake.nix treefmt.nix

# Format code
fmt:
    stylua lua tests plugin
    yamlfmt -gitignore_excludes .
    prettier --write "**/*.{json,jsonc}"
    tombi format --offline .
    nixfmt flake.nix treefmt.nix

# Run selene
# plugin/ has its own selene.toml (std = "wezterm", not "vim"), so it's linted from inside that
# directory: selene resolves its config by walking up from cwd, and the repo-root selene.toml
# would otherwise shadow it.
lint:
    selene ./lua/ ./tests/
    cd plugin && selene .
    actionlint
    statix check

# Run LuaLS type checking
# plugin/ is excluded from the root check via .luarc.json's ignoreDir and checked separately
# against its own .luarc.json (globals = ["wezterm"], not ["vim"]).
typecheck: deps
    #!/usr/bin/env bash
    set -euo pipefail
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT
    VIMRUNTIME="$(nvim --clean -i NONE --headless --cmd 'lua io.write(vim.env.VIMRUNTIME)' --cmd 'quitall')" \
    lua-language-server --check=. --checklevel=Warning --check_format=pretty --configpath=.luarc.json --logpath="$tmpdir/luals"
    lua-language-server --check=./plugin --checklevel=Warning --check_format=pretty --configpath=./plugin/.luarc.json --logpath="$tmpdir/luals-plugin"

# Run all checks
check: fmt-check lint typecheck test
