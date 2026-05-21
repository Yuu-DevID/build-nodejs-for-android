#!/system/bin/sh
# npm wrapper for Android (Bionic shell)
# Usage: identical to regular npm
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE_BIN="$SCRIPT_DIR/node"
NPM_CLI="$SCRIPT_DIR/../lib/node_modules/npm/bin/npm-cli.js"

export HOME="${HOME:-/data/local/tmp}"
export NODE_REPL_HISTORY="$HOME/.node_history"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export LD_LIBRARY_PATH="$SCRIPT_DIR:${LD_LIBRARY_PATH:-}"

mkdir -p "$NPM_CONFIG_PREFIX/bin" "$NPM_CONFIG_PREFIX/lib"

if [ ! -f "$NODE_BIN" ]; then
  echo "error: node not found at $NODE_BIN" >&2
  exit 1
fi

if [ ! -f "$NPM_CLI" ]; then
  echo "error: npm-cli.js not found at $NPM_CLI" >&2
  exit 1
fi

exec "$NODE_BIN" "$NPM_CLI" "$@"
