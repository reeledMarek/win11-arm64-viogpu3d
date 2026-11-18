#!/usr/bin/env bash
# Cross-compile Mesa ARM64EC objects/archives needed to build ARM64X hybrid DLLs
# (enabling emulated x64 processes such as x64 Java/Minecraft to load Mesa OpenGL/D3D10/Vulkan).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src/virtio-win-mesa"
WORK="$ROOT/obj-mesa"
SCRIPTS="$ROOT/scripts"
JOBS="${MESA_JOBS:-4}"

export PATH="$ROOT/toolchain/llvm-mingw/bin:$PATH"
export SOURCE_DATE_EPOCH=0
export TZ=UTC
export LC_ALL=C.UTF-8

prefix_map="-ffile-prefix-map=$WORK=/mesa"
ldflags="-static -Wl,--no-insert-timestamp"

b="$WORK/build-arm64ec"
p="$WORK/prefix-arm64ec"
if [ "${CLEAN:-0}" = "1" ] || [ ! -f "$b/build.ninja" ]; then
  rm -rf "$b" "$p"
  echo "=== Configuring Mesa (arm64ec) ==="
  meson setup "$b" "$SRC" --cross-file "$SCRIPTS/meson-arm64ec.ini" \
    --buildtype=release --prefix="$p" --wrap-mode=nodownload \
    -Dc_args="$prefix_map" -Dcpp_args="$prefix_map" \
    -Dc_link_args="$ldflags" -Dcpp_link_args="$ldflags" \
    -Dplatforms=windows -Dgallium-drivers=zink \
    -Dgallium-yttrium=true -Dgallium-d3d10umd=true \
    -Dgallium-wgl-dll-name=viogpu_wgl -Dgallium-d3d10-dll-name=viogpu_d3d10 \
    -Dvulkan-drivers=virtio -Dllvm=disabled -Dzlib=disabled -Dzstd=disabled \
    -Dexpat=disabled -Dbuild-tests=false
fi

echo "=== Building Mesa (arm64ec) ==="
ninja -C "$b" -j "$JOBS" \
  src/gallium/targets/d3d10umd/viogpu_d3d10.dll \
  src/gallium/targets/wgl/viogpu_wgl.dll \
  src/virtio/vulkan/libvulkan_virtio.dll
