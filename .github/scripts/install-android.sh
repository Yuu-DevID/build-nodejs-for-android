#!/system/bin/sh
# Install Node.js on Android
# Run on device: adb push . /data/local/tmp/nodejs/ && adb shell sh /data/local/tmp/nodejs/install.sh
# Or from adb shell directly after pushing the files.
set -e

INSTALL_DIR="/data/local/tmp/nodejs"
PROFILE_FILE="$HOME/.profile"

# ── Validate environment ──────────────────────────────────────────────────────
if [ ! -f "bin/node" ]; then
  echo "error: bin/node not found. Run this script from the package directory." >&2
  exit 1
fi

echo "=== Node.js Android Installer ==="
echo "Target: $INSTALL_DIR"
echo ""

# ── Copy files ────────────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib"

cp -f bin/node           "$INSTALL_DIR/bin/node"
cp -f bin/npm            "$INSTALL_DIR/bin/npm"
cp -f bin/npx            "$INSTALL_DIR/bin/npx"
chmod 755 "$INSTALL_DIR/bin/node" \
          "$INSTALL_DIR/bin/npm"  \
          "$INSTALL_DIR/bin/npx"

# libc++_shared.so (required if not already on system LD_LIBRARY_PATH)
if [ -f "bin/libc++_shared.so" ]; then
  cp -f bin/libc++_shared.so "$INSTALL_DIR/bin/"
  chmod 755 "$INSTALL_DIR/bin/libc++_shared.so"
  echo "Copied libc++_shared.so"
fi

# npm modules (node_modules, corepack, etc.)
if [ -d "lib" ]; then
  cp -r lib/. "$INSTALL_DIR/lib/"
  chmod -R 755 "$INSTALL_DIR/lib"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "Verifying installation..."
export LD_LIBRARY_PATH="$INSTALL_DIR/bin:${LD_LIBRARY_PATH:-}"
export HOME="${HOME:-/data/local/tmp}"

NODE_VER=$("$INSTALL_DIR/bin/node" --version 2>&1) || {
  echo "error: node binary failed to execute. Check ABI compatibility." >&2
  exit 1
}
echo "  node  $NODE_VER"
NPM_VER=$("$INSTALL_DIR/bin/node" \
  "$INSTALL_DIR/lib/node_modules/npm/bin/npm-cli.js" --version 2>&1) || true
[ -n "$NPM_VER" ] && echo "  npm   v$NPM_VER"

# ── Write env snippet to .profile ────────────────────────────────────────────
ENV_BLOCK="
# Node.js Android — added by install.sh
export HOME=\"/data/local/tmp\"
export LD_LIBRARY_PATH=\"$INSTALL_DIR/bin:\$LD_LIBRARY_PATH\"
export PATH=\"$INSTALL_DIR/bin:\$PATH\"
export NPM_CONFIG_PREFIX=\"\$HOME/.npm-global\"
export PATH=\"\$NPM_CONFIG_PREFIX/bin:\$PATH\"
"

if [ -f "$PROFILE_FILE" ]; then
  if ! grep -q "Node.js Android" "$PROFILE_FILE" 2>/dev/null; then
    printf '%s\n' "$ENV_BLOCK" >> "$PROFILE_FILE"
    echo "Environment written to $PROFILE_FILE"
  else
    echo "Environment already in $PROFILE_FILE — skipped"
  fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "=== Installation Complete ==="
echo ""
echo "Add to your session (or source $PROFILE_FILE):"
echo "  export HOME=/data/local/tmp"
echo "  export LD_LIBRARY_PATH=$INSTALL_DIR/bin:\$LD_LIBRARY_PATH"
echo "  export PATH=$INSTALL_DIR/bin:\$PATH"
echo ""
echo "Run:"
echo "  node --version"
echo "  npm  install <package>"
echo "  npx  <tool>"
