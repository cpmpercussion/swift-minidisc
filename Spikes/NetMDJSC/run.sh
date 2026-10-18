#!/bin/sh
# Build the JS bundle and the spike, sign it with hardened runtime + allow-jit, run it.
# Without allow-jit, JavaScriptCore runs interpreter-only (~30x slower upload encryption).
set -e
cd "$(dirname "$0")"
[ -d node_modules ] || npm install --no-audit --no-fund
npm run build --silent
swift build -c release
BIN="$(swift build -c release --show-bin-path)/netmd-jsc-spike"
codesign --force -s - -o runtime --entitlements NetMDJSC.entitlements "$BIN"
exec "$BIN" "$@"
