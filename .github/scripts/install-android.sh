#!/system/bin/sh
# Install Node.js on Android
# Run on device or via: adb shell sh install.sh

INSTALL_DIR="/data/local/tmp"
echo "Installing Node.js to $INSTALL_DIR..."

cp bin/node "$INSTALL_DIR/"
cp bin/npm-android "$INSTALL_DIR/npm"
cp bin/npx-android "$INSTALL_DIR/npx"
chmod 755 "$INSTALL_DIR/node" "$INSTALL_DIR/npm" "$INSTALL_DIR/npx"

if [ -f "bin/libc++_shared.so" ]; then
  cp bin/libc++_shared.so "$INSTALL_DIR/"
  chmod 755 "$INSTALL_DIR/libc++_shared.so"
fi

cp -r lib "$INSTALL_DIR/"
chmod -R 755 "$INSTALL_DIR/lib"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "To use Node.js on Android:"
echo "  export HOME=/data/local/tmp"
echo "  export NODE_REPL_HISTORY=\$HOME/node_history"
echo "  export LD_LIBRARY_PATH=/data/local/tmp:\$LD_LIBRARY_PATH"
echo "  /data/local/tmp/node --version"
echo ""
echo "To use npm:"
echo "  /data/local/tmp/npm install <package>"
