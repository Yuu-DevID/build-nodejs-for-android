#!/system/bin/sh
# npx wrapper for Android (Bionic shell)
# Usage: identical to regular npx
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE_BIN="$SCRIPT_DIR/node"
NPX_CLI="$SCRIPT_DIR/../lib/node_modules/npm/bin/npx-cli.js"

export HOME="${HOME:-/data/local/tmp}"
export NODE_REPL_HISTORY="$HOME/.node_history"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export LD_LIBRARY_PATH="$SCRIPT_DIR:${LD_LIBRARY_PATH:-}"

mkdir -p "$NPM_CONFIG_PREFIX/bin" "$NPM_CONFIG_PREFIX/lib"

if [ ! -f "$NODE_BIN" ]; then
  echo "error: node not found at $NODE_BIN" >&2
  exit 1
fi

if [ ! -f "$NPX_CLI" ]; then
  echo "error: npx-cli.js not found at $NPX_CLI" >&2
  exit 1
fi

exec "$NODE_BIN" "$NPX_CLI" "$@"
