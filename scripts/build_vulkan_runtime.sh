#!/usr/bin/env bash
# Cross-compile Vulkan-Loader (vulkan-1.dll) and Vulkan-Tools (vulkaninfo.exe)
# for Windows 11 ARM64 and WoW64 (x86).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/cache"
SRC="$ROOT/src/vulkan-sdk"
WORK="$ROOT/obj-vulkan"
OUT="$ROOT/out/vulkan-sdk"
SCRIPTS="$ROOT/scripts"
TAG=vulkan-sdk-1.4.363.0
VER=1.4.363.0

export PATH="$ROOT/toolchain/llvm-mingw/bin:$PATH"
export SOURCE_DATE_EPOCH=1789748904
export TZ=UTC
export LC_ALL=C.UTF-8

mkdir -p "$CACHE" "$SRC" "$WORK" "$OUT"
for repo in Vulkan-Headers Vulkan-Loader Vulkan-Tools; do
  if [ "${CLEAN_SRC:-0}" = "1" ] || [ ! -f "$SRC/$repo/CMakeLists.txt" ]; then
    f="$CACHE/$repo-$TAG.tar.gz"
    if [ ! -f "$f" ]; then
      curl -fsSL --retry 3 -o "$f.part" "https://github.com/KhronosGroup/$repo/archive/refs/tags/$TAG.tar.gz"
      mv "$f.part" "$f"
    fi
    rm -rf "$SRC/$repo"
    mkdir -p "$SRC/$repo"
    tar -C "$SRC/$repo" --strip-components=1 -xzf "$f"
  fi
done

# Fix vulkaninfo MinGW/Clang User32 handles init (skip if already applied)
if ! grep -q 'LoadLibraryExA("user32.dll"' "$SRC/Vulkan-Tools/vulkaninfo/vulkaninfo.h"; then
  curl -fsSL "https://raw.githubusercontent.com/VMLabDev/vmlab/HEAD/guest/win32/patches/vulkan-tools/0001-vulkaninfo-Load-user32-on-every-Windows-compiler.patch" \
    -o "$WORK/0001-vulkaninfo-user32.patch" || \
  curl -fsSL "https://raw.githubusercontent.com/VMLabDev/vmlab/HEAD/guest/win3d/patches/vulkan-tools/0001-vulkaninfo-Load-user32-on-every-Windows-compiler.patch" \
    -o "$WORK/0001-vulkaninfo-user32.patch"
  patch --directory="$SRC/Vulkan-Tools" --strip=1 --forward --batch --quiet < "$WORK/0001-vulkaninfo-user32.patch"
fi

HDR="$WORK/headers"
rm -rf "$WORK/build-headers" "$HDR"
cmake -S "$SRC/Vulkan-Headers" -B "$WORK/build-headers" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$SCRIPTS/cmake-aarch64.cmake" \
  -DCMAKE_INSTALL_PREFIX="$HDR" -DVULKAN_HEADERS_ENABLE_MODULE=OFF \
  -DVULKAN_HEADERS_ENABLE_TESTS=OFF
cmake --install "$WORK/build-headers"

cflags="-O2 -ffile-prefix-map=$WORK=/vulkan-sdk"
ldflags="-static -s -Wl,--no-insert-timestamp"

build_arch() {
  local triple=$1 dir=$2
  local tc="$SCRIPTS/cmake-$triple.cmake"
  local bl="$WORK/build-$dir-loader" bt="$WORK/build-$dir-tools"
  rm -rf "$bl" "$bt" "$OUT/$dir"
  local common=(
    -G Ninja
    -DCMAKE_TOOLCHAIN_FILE="$tc"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_FLAGS="$cflags"
    -DCMAKE_CXX_FLAGS="$cflags"
    -DCMAKE_ASM_FLAGS="-ffile-prefix-map=$WORK=/vulkan-sdk"
    -DCMAKE_EXE_LINKER_FLAGS="$ldflags"
    -DCMAKE_SHARED_LINKER_FLAGS="$ldflags"
    -DCMAKE_C_FLAGS_RELEASE=-DNDEBUG
    -DCMAKE_CXX_FLAGS_RELEASE=-DNDEBUG
    -DVulkanHeaders_DIR="$HDR/share/cmake/VulkanHeaders"
  )
  cmake -S "$SRC/Vulkan-Loader" -B "$bl" "${common[@]}" \
    -DBUILD_DLL_VERSIONINFO="$VER" \
    -DUSE_GAS=ON -DBUILD_TESTS=OFF -DLOADER_CODEGEN=OFF -DUPDATE_DEPS=OFF
  cmake --build "$bl" --target vulkan -j 2

  cmake -S "$SRC/Vulkan-Tools" -B "$bt" "${common[@]}" \
    -DVULKANINFO_BUILD_DLL_VERSIONINFO="$VER" \
    -DBUILD_CUBE=OFF -DBUILD_ICD=OFF -DBUILD_TESTS=OFF -DBUILD_VULKANINFO=ON \
    -DUPDATE_DEPS=OFF
  cmake --build "$bt" --target vulkaninfo -j 2

  mkdir -p "$OUT/$dir"
  cp "$bl/loader/vulkan-1.dll" "$OUT/$dir/"
  cp "$bt/vulkaninfo/vulkaninfo.exe" "$OUT/$dir/"
}

build_arch aarch64 arm64
build_arch i686 x86

file "$OUT"/arm64/* "$OUT"/x86/*
