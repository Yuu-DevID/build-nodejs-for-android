#!/system/bin/sh
# npx wrapper for Android
export HOME=/data/local/tmp
export NODE_REPL_HISTORY=$HOME/node_history
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p $HOME/npm-global 2>/dev/null
export NPM_CONFIG_PREFIX=$HOME/npm-global
exec "$SCRIPT_DIR/node" "$SCRIPT_DIR/../lib/node_modules/npm/bin/npx-cli.js" "$@"
