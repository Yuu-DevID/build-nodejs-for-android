#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# Configuration — semua bisa di-override via env
# ─────────────────────────────────────────────
NODE_VERSION="${NODE_VERSION:-26.2.0}"
ME="node-v${NODE_VERSION}"

# GitHub Actions Ubuntu 22.04 sudah punya NDK pre-installed
NDK="${NDK:-/usr/local/lib/android/sdk/ndk/29.0.14206865}"
ANDROID_SDK_VER="${ANDROID_SDK_VER:-24}"
ARCH="${ARCH:-arm64}"        # arm64 | arm | x86 | x86_64
DIST_DIR="${DIST_DIR:-/output}"
WORKDIR="${WORKDIR:-/tmp/node-build}"
JOBS="${JOBS:-$(nproc)}"

# ─────────────────────────────────────────────
# Validate
# ─────────────────────────────────────────────
if [[ ! -d "$NDK" ]]; then
  echo "[ERROR] NDK not found: $NDK"
  echo "        Set env var NDK= ke path yang benar."
  echo "        Available NDK di runner:"
  ls /usr/local/lib/android/sdk/ndk/ 2>/dev/null || true
  exit 1
fi

if [[ "$ANDROID_SDK_VER" -lt 24 ]]; then
  echo "[ERROR] Node.js v22+ butuh Android SDK >= 24 (got $ANDROID_SDK_VER)"
  exit 1
fi

# Normalize arch alias
case "$ARCH" in
  aarch64) ARCH="arm64" ;;
  x64)     ARCH="x86_64" ;;
esac

echo "======================================"
echo " Building Node.js v${NODE_VERSION}"
echo " Arch      : $ARCH"
echo " SDK level : $ANDROID_SDK_VER"
echo " NDK       : $NDK"
echo " Jobs      : $JOBS"
echo " Output    : $DIST_DIR"
echo "======================================"

# ─────────────────────────────────────────────
# Download / reuse source tarball
# ─────────────────────────────────────────────
mkdir -p "$WORKDIR"
TARBALL="$WORKDIR/$ME.tar.gz"

if [[ ! -f "$TARBALL" ]]; then
  echo "[*] Downloading Node.js v${NODE_VERSION}..."
  curl -fL --retry 3 \
    -o "$TARBALL" \
    "https://nodejs.org/dist/v${NODE_VERSION}/${ME}.tar.gz"
fi

echo "[*] Extracting source..."
cd "$WORKDIR"
rm -rf "$ME"
tar -xzf "$TARBALL"
cd "$ME"

# ─────────────────────────────────────────────
# Host compilers (WAJIB sebelum android-configure)
# android-configure set CC/CXX ke NDK cross-compiler,
# tapi host tools (icupkg, mksnapshot) butuh compiler host x86_64
# ─────────────────────────────────────────────
export CC_host="$(which gcc)"
export CXX_host="$(which g++)"

# ─────────────────────────────────────────────
# Patch trap-handler sebelum configure
# (Node menyediakan patch resmi via android-patches/)
# ─────────────────────────────────────────────
echo "[*] Applying android patches..."
python3 android-configure patch 2>/dev/null || true

# ─────────────────────────────────────────────
# V8 patches untuk Android cross-compilation
# ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/.github/scripts"

if [[ -f "$PATCH_DIR/stack_trace_posix.patch" ]] && \
   [[ -f "deps/v8/src/base/debug/stack_trace_posix.cc" ]]; then
  echo "[*] Applying stack_trace_posix.patch..."
  patch -p1 < "$PATCH_DIR/stack_trace_posix.patch"
fi

if [[ -f "$PATCH_DIR/v8config-h.patch" ]] && \
   [[ -f "deps/v8/include/v8config.h" ]]; then
  echo "[*] Applying v8config-h.patch..."
  patch -p1 < "$PATCH_DIR/v8config-h.patch"
fi

if [[ -f "$PATCH_DIR/globals-h.patch" ]] && \
   [[ -f "deps/v8/src/common/globals.h" ]]; then
  echo "[*] Applying globals-h.patch..."
  patch -p1 < "$PATCH_DIR/globals-h.patch"
fi

# ─────────────────────────────────────────────
# Configure via android-configure resmi Node.js
# Format: android-configure <NDK_PATH> <SDK_VER> <ARCH>
# android-configure juga set GYP_DEFINES + CC/CXX otomatis
# (termasuk OS=android, jadi libuv pilih source yg benar)
# ─────────────────────────────────────────────
echo "[*] Running android-configure $NDK $ANDROID_SDK_VER $ARCH ..."
python3 android-configure "$NDK" "$ANDROID_SDK_VER" "$ARCH"

# ─────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────
echo "[*] Building dengan $JOBS jobs..."
make -j"$JOBS"

# ─────────────────────────────────────────────
# Package output
# ─────────────────────────────────────────────
echo "[*] Packaging..."
OUT_DIR="$DIST_DIR/${ME}-android-${ARCH}"
mkdir -p "$OUT_DIR/lib" "$OUT_DIR/include"

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
STRIP_BIN="$TOOLCHAIN/llvm-strip"

# Cari libnode.so
LIBNODE=$(find out/Release -maxdepth 3 \( -name "libnode.so" -o -name "libnode.so.*" \) 2>/dev/null | head -1)
if [[ -n "$LIBNODE" ]]; then
  cp -v "$LIBNODE" "$OUT_DIR/lib/"
  "$STRIP_BIN" --strip-unneeded "$OUT_DIR/lib/$(basename "$LIBNODE")" 2>/dev/null || \
    strip --strip-unneeded "$OUT_DIR/lib/$(basename "$LIBNODE")" || true
  echo "[*] libnode.so size: $(du -sh "$OUT_DIR/lib/$(basename "$LIBNODE")" | cut -f1)"
else
  echo "[WARN] libnode.so tidak ditemukan, cek apakah --shared berhasil."
  find out/Release -maxdepth 3 -name "*.so*" 2>/dev/null || true
fi

# Copy headers
[[ -d "include" ]] && cp -r include/. "$OUT_DIR/include/"

# Buat tarball
TAROUT="${ME}-android-${ARCH}.tar.gz"
mkdir -p "$DIST_DIR"
cd "$DIST_DIR"
tar -czf "$TAROUT" "$(basename "$OUT_DIR")/"

echo ""
echo "======================================"
echo " DONE!"
echo " File  : $DIST_DIR/$TAROUT"
echo " Size  : $(du -sh "$TAROUT" | cut -f1)"
echo "======================================"
