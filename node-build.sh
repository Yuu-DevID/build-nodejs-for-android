#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────
NODE_VERSION="${NODE_VERSION:-26.2.0}"
ME="node-v${NODE_VERSION}"
NDK="${NDK:-/github/build-nodejs/android-ndk-r29b}"
ENVHOST="${ENVHOST:-linux-x86_64}"
ENVTARGET="${ENVTARGET:-aarch64-linux-android}"
ENVANDROIDVER="${ENVANDROIDVER:-24}"
DIST_DIR="${DIST_DIR:-/output}"

MEDIR="$(cd "$(dirname "$0")"; pwd)"
COMPILERDIR="$NDK/toolchains/llvm/prebuilt/$ENVHOST/bin"

# ─────────────────────────────────────────────
# Resolve arch params from ENVTARGET
# ─────────────────────────────────────────────
case "$ENVTARGET" in
  aarch64-linux-android)
    ARCH="arm64"
    DEST_CPU="arm64"
    ;;
  armv7a-linux-androideabi)
    ARCH="arm"
    DEST_CPU="arm"
    ;;
  i686-linux-android)
    ARCH="ia32"
    DEST_CPU="ia32"
    ;;
  x86_64-linux-android)
    ARCH="x64"
    DEST_CPU="x64"
    ;;
  *)
    echo "[ERROR] Unknown ENVTARGET: $ENVTARGET"
    exit 1
    ;;
esac

echo "======================================"
echo " Building Node.js v${NODE_VERSION}"
echo " Target : $ENVTARGET ($ARCH)"
echo " NDK    : $NDK"
echo " Output : $DIST_DIR"
echo "======================================"

# ─────────────────────────────────────────────
# Export cross-compile toolchain
# ─────────────────────────────────────────────
export CC="$COMPILERDIR/${ENVTARGET}${ENVANDROIDVER}-clang"
export CXX="$COMPILERDIR/${ENVTARGET}${ENVANDROIDVER}-clang++"
export LD="$COMPILERDIR/llvm-lld"
export AS="$COMPILERDIR/$ENVTARGET-as"
export AR="$COMPILERDIR/llvm-ar"
export STRIP="$COMPILERDIR/llvm-strip"
export OBJCOPY="$COMPILERDIR/llvm-objcopy"
export OBJDUMP="$COMPILERDIR/llvm-objdump"
export RANLIB="$COMPILERDIR/llvm-ranlib"
export NM="$COMPILERDIR/llvm-nm"
export STRINGS="$COMPILERDIR/llvm-strings"
export READELF="$COMPILERDIR/llvm-readelf"

# For armv7a the clang binary name uses a slightly different pattern
if [[ "$ENVTARGET" == "armv7a-linux-androideabi" ]]; then
  export CC="$COMPILERDIR/armv7a-linux-androideabi${ENVANDROIDVER}-clang"
  export CXX="$COMPILERDIR/armv7a-linux-androideabi${ENVANDROIDVER}-clang++"
fi

# Verify toolchain exists
if [[ ! -f "$CC" ]]; then
  echo "[ERROR] Compiler not found: $CC"
  echo "        Check NDK path and ENVTARGET/ENVANDROIDVER values."
  exit 1
fi

# Host compilers (system gcc, already installed in Docker image)
export CC_host="$(which gcc)"
export CXX_host="$(which g++)"
export AR_host="$(which ar)"
export RANLIB_host="$(which ranlib)"

# ─────────────────────────────────────────────
# Download source
# ─────────────────────────────────────────────
TARBALL="$ME.tar.gz"
TARBALL_URL="https://nodejs.org/dist/v${NODE_VERSION}/${TARBALL}"
WORKDIR="/tmp/node-build"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [[ ! -f "$TARBALL" ]]; then
  echo "[*] Downloading $TARBALL_URL ..."
  curl -fL --retry 3 -o "$TARBALL" "$TARBALL_URL"
fi

echo "[*] Extracting source..."
rm -rf "$ME"
tar -xzf "$TARBALL"
cd "$ME"

# ─────────────────────────────────────────────
# GYP defines
# ─────────────────────────────────────────────
export GYP_DEFINES="target_arch=$ARCH"
GYP_DEFINES+=" v8_target_arch=$ARCH"
GYP_DEFINES+=" android_target_arch=$ARCH"
GYP_DEFINES+=" host_os=linux OS=android"
GYP_DEFINES+=" android_ndk_path=$NDK"
export GYP_DEFINES

# ─────────────────────────────────────────────
# Configure
# ─────────────────────────────────────────────
echo "[*] Running configure..."
./configure \
  --prefix="$DIST_DIR/$ME-$ARCH" \
  --dest-cpu="$DEST_CPU" \
  --dest-os=android \
  --openssl-no-asm \
  --cross-compiling \
  --shared

# ─────────────────────────────────────────────
# V8 patches for Android cross-compilation
# ─────────────────────────────────────────────

PATCH_DIR="$MEDIR/.github/scripts"

# V8 stack_trace patch — fixes backtrace on Android Bionic
if [[ -f "$PATCH_DIR/stack_trace_posix.patch" ]] && \
   [[ -f "deps/v8/src/base/debug/stack_trace_posix.cc" ]]; then
  echo "[*] Applying stack_trace_posix.patch..."
  patch -p1 < "$PATCH_DIR/stack_trace_posix.patch"
fi

# v8config.h patch — allow ARM target on x64 host
if [[ -f "$PATCH_DIR/v8config-h.patch" ]] && \
   [[ -f "deps/v8/include/v8config.h" ]]; then
  echo "[*] Applying v8config-h.patch..."
  patch -p1 < "$PATCH_DIR/v8config-h.patch"
fi

# globals.h patch — fix TAGGED_SIZE_8_BYTES for cross-compilation
if [[ -f "$PATCH_DIR/globals-h.patch" ]] && \
   [[ -f "deps/v8/src/common/globals.h" ]]; then
  echo "[*] Applying globals-h.patch..."
  patch -p1 < "$PATCH_DIR/globals-h.patch"
fi

# ─────────────────────────────────────────────
# Patches (same as original, preserved)
# ─────────────────────────────────────────────

# Fix LD_LIBRARY_PATH references in generated makefiles
grep -rl "LD_LIBRARY_PATH=" . \
  | grep -v Binary \
  | xargs --no-run-if-empty sed -i "s|LD_LIBRARY_PATH=|LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:|g"

# Ensure epoll.o is linked for libuv
if grep -q "poll.o \\\\" out/deps/uv/libuv.target.mk 2>/dev/null; then
  sed -i 's|/poll.o \\|/poll.o \\\n\t$(obj).target/$(TARGET)/deps/uv/src/unix/epoll.o \\|' \
    out/deps/uv/libuv.target.mk
fi

# Disable V8 trap handler (not supported on Android cross-compile)
TRAP_HEADER="deps/v8/src/trap-handler/trap-handler.h"
if grep -q "Setup for shared library export" "$TRAP_HEADER" 2>/dev/null; then
  sed -i "s|// Setup for shared library export.|#undef V8_TRAP_HANDLER_VIA_SIMULATOR\n#undef V8_TRAP_HANDLER_SUPPORTED\n#define V8_TRAP_HANDLER_SUPPORTED false\n\n// Setup for shared library export.|" \
    "$TRAP_HEADER"
fi

# ─────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────
JOBS="${JOBS:-$(nproc)}"
echo "[*] Building with $JOBS parallel jobs..."
make -j"$JOBS"

# ─────────────────────────────────────────────
# Package output
# ─────────────────────────────────────────────
echo "[*] Packaging output..."
mkdir -p "$DIST_DIR"

# Copy the shared library
LIBNODE=$(find out/Release -name "libnode.so" -o -name "libnode.so.*" 2>/dev/null | head -1)
if [[ -n "$LIBNODE" ]]; then
  mkdir -p "$DIST_DIR/$ME-$ARCH/lib"
  cp -v "$LIBNODE" "$DIST_DIR/$ME-$ARCH/lib/"
  "$STRIP" --strip-unneeded "$DIST_DIR/$ME-$ARCH/lib/$(basename "$LIBNODE")" || true
fi

# Copy headers
if [[ -d "include" ]]; then
  cp -r include "$DIST_DIR/$ME-$ARCH/"
fi

# Create tarball
cd "$DIST_DIR"
TAROUT="${ME}-android-${ARCH}.tar.gz"
tar -czf "$TAROUT" "$ME-$ARCH/"
echo ""
echo "======================================"
echo " Done! Output: $DIST_DIR/$TAROUT"
echo "======================================"
