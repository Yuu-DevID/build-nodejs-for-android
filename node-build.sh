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

# Capture repo dir BEFORE any cd (patches live here)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
PATCH_DIR="$SCRIPT_DIR/.github/scripts"

apply_patch() {
  local patch_file="$1"
  local target_file="$2"
  if [[ ! -f "$patch_file" ]]; then
    echo "[SKIP] Patch not found: $patch_file"
    return 0
  fi
  if [[ ! -f "$target_file" ]]; then
    echo "[SKIP] Target not found: $target_file"
    return 0
  fi
  echo "[*] Applying $(basename "$patch_file")..."
  if patch -p1 --dry-run < "$patch_file" >/dev/null 2>&1; then
    patch -p1 < "$patch_file"
    echo "[OK] $(basename "$patch_file") applied"
  else
    echo "[WARN] $(basename "$patch_file") does not apply cleanly — skipping"
  fi
}

apply_patch "$PATCH_DIR/stack_trace_posix.patch" \
            "deps/v8/src/base/debug/stack_trace_posix.cc"

apply_patch "$PATCH_DIR/v8config-h.patch" \
            "deps/v8/include/v8config.h"

# globals-h.patch: relaxed cross-compilation assertion in globals.h
# Host tools have kTaggedSize=8 (x86_64) but TAGGED_SIZE_8_BYTES=false
# (ARM target), causing static_assert failure during cross-compilation
apply_patch "$PATCH_DIR/globals-h.patch" \
            "deps/v8/src/common/globals.h"

# builtins-iterator.patch: GCC evaluates static_assert in discarded
# if constexpr branches (GCC bug). Replace static_assert with if constexpr.
apply_patch "$PATCH_DIR/builtins-iterator.patch" \
            "deps/v8/src/builtins/builtins-iterator-inl.h"

# ─────────────────────────────────────────────
# Configure for Android cross-compilation
# ─────────────────────────────────────────────
# Map arch to DEST_CPU and toolchain prefix
case "$ARCH" in
  arm64)   DEST_CPU="arm64";  TOOLCHAIN_PREFIX="aarch64-linux-android" ;;
  arm)     DEST_CPU="arm";    TOOLCHAIN_PREFIX="armv7a-linux-androideabi" ;;
  x86)     DEST_CPU="ia32";   TOOLCHAIN_PREFIX="i686-linux-android" ;;
  x86_64)  DEST_CPU="x64";    TOOLCHAIN_PREFIX="x86_64-linux-android" ;;
esac

TOOLCHAIN_PATH="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
export CC="$TOOLCHAIN_PATH/bin/${TOOLCHAIN_PREFIX}${ANDROID_SDK_VER}-clang"
export CXX="$TOOLCHAIN_PATH/bin/${TOOLCHAIN_PREFIX}${ANDROID_SDK_VER}-clang++"
export CC_host="$(which gcc)"
export CXX_host="$(which g++)"

# Set GYP_DEFINES same as android_configure.py, plus pointer compression
# Pointer compression forces 32-bit Smis on host+target, fixing the
# kTaggedSize/SmiValuesAre31Bits assertion failures in host tools
export GYP_DEFINES="target_arch=$DEST_CPU v8_target_arch=$DEST_CPU android_target_arch=$DEST_CPU host_os=linux OS=android android_ndk_path=$NDK v8_enable_pointer_compression=1 v8_enable_31bit_smis_on_64bit_arch=1"

echo "[*] Configuring for $DEST_CPU (Android SDK $ANDROID_SDK_VER) ..."
./configure --dest-cpu="$DEST_CPU" --dest-os=android --openssl-no-asm --cross-compiling \
  --experimental-enable-pointer-compression

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
