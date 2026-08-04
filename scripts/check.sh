#!/usr/bin/env bash
# Everything there is to run: luacheck over every file the client loads, then busted.
# Zero warnings and zero failures before committing.
set -euo pipefail
cd "$(dirname "$0")/.."

eval "$(luarocks --lua-version 5.1 path --bin 2>/dev/null || true)"

echo "==> luacheck"
luacheck chronie/src chronie/Main.lua spec

echo "==> busted"
busted --verbose
