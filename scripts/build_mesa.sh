#!/usr/bin/env bash
# Cross-compile Yttrium Mesa UMDs (viogpu_d3d10.dll, viogpu_wgl.dll, libvulkan_virtio.dll)
# for Windows 11 ARM64 (aarch64) and WoW64 (x86).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src/virtio-win-mesa"
OUT="$ROOT/out/mesa"
WORK="$ROOT/obj-mesa"
SCRIPTS="$ROOT/scripts"
JOBS="${MESA_JOBS:-4}"

export PATH="$ROOT/toolchain/llvm-mingw/bin:$PATH"
export SOURCE_DATE_EPOCH=0
export TZ=UTC
export LC_ALL=C.UTF-8

prefix_map="-ffile-prefix-map=$WORK=/mesa"
ldflags="-static -Wl,--no-insert-timestamp"

build_arch() {
  local triple=$1 dir=$2 icdarch=$3 bits=$4
  local b="$WORK/build-$dir"
  local p="$WORK/prefix-$dir"
  if [ "${CLEAN:-0}" = "1" ] || [ ! -f "$b/build.ninja" ]; then
    rm -rf "$b" "$p"
    echo "=== Configuring Mesa ($dir / $triple) ==="
    meson setup "$b" "$SRC" --cross-file "$SCRIPTS/meson-$triple.ini" \
      --buildtype=release --prefix="$p" --wrap-mode=nodownload \
      -Dc_args="$prefix_map" -Dcpp_args="$prefix_map" \
      -Dc_link_args="$ldflags" -Dcpp_link_args="$ldflags" \
      -Dplatforms=windows -Dgallium-drivers=zink \
      -Dgallium-yttrium=true -Dgallium-d3d10umd=true \
      -Dgallium-wgl-dll-name=viogpu_wgl -Dgallium-d3d10-dll-name=viogpu_d3d10 \
      -Dvulkan-drivers=virtio -Dllvm=disabled -Dzlib=disabled -Dzstd=disabled \
      -Dexpat=disabled -Dbuild-tests=false
  fi
  rm -rf "$OUT/$dir"

  echo "=== Building Mesa ($dir) ==="
  ninja -C "$b" -j "$JOBS" \
    src/gallium/targets/d3d10umd/viogpu_d3d10.dll \
    src/gallium/targets/wgl/viogpu_wgl.dll \
    "src/virtio/vulkan/libvulkan_virtio.dll" \
    "src/virtio/vulkan/virtio_icd.$icdarch.json"

  mkdir -p "$OUT/$dir"
  for dll in src/gallium/targets/d3d10umd/viogpu_d3d10.dll \
             src/gallium/targets/wgl/viogpu_wgl.dll \
             src/virtio/vulkan/libvulkan_virtio.dll; do
    "$ROOT/toolchain/llvm-mingw/bin/llvm-strip" --strip-unneeded -o "$OUT/$dir/$(basename "$dll")" "$b/$dll"
  done

  local api
  api="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ICD"]["api_version"])' \
    "$b/src/virtio/vulkan/virtio_icd.$icdarch.json")"
  printf '{\n    "file_format_version": "1.0.1",\n    "ICD": {\n        "library_path": ".\\\\libvulkan_virtio.dll",\n        "library_arch": "%s",\n        "api_version": "%s"\n    }\n}\n' \
    "$bits" "$api" > "$OUT/$dir/virtio_icd.$icdarch.json"
}

build_arch aarch64 arm64 aarch64 64
build_arch i686 x86 i686 32

ls -lh "$OUT/arm64" "$OUT/x86"
file "$OUT"/arm64/*.dll "$OUT"/x86/*.dll
