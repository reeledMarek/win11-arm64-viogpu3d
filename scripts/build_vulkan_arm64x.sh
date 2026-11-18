#!/usr/bin/env bash
# Build ARM64EC Vulkan-Loader + x64 vulkaninfo.exe and link ARM64X vulkan-1.dll.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
SRC="$ROOT/src/vulkan-sdk"
WORK="$ROOT/obj-vulkan"
HDR="$WORK/headers"
LIBDIR="$ROOT/toolchain/llvm-mingw/aarch64-w64-mingw32/lib"
RT="$ROOT/toolchain/llvm-mingw/lib/clang/23/lib/windows/libclang_rt.builtins-aarch64.a"
export PATH="$ROOT/toolchain/llvm-mingw/bin:$PATH"

cflags="-O2 -ffile-prefix-map=$WORK=/vulkan-sdk"
ldflags="-static -s -Wl,--no-insert-timestamp"

BL_EC="$WORK/build-arm64ec-loader"
rm -rf "$BL_EC"
cmake -S "$SRC/Vulkan-Loader" -B "$BL_EC" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$SCRIPTS/cmake-arm64ec.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$cflags" \
  -DCMAKE_CXX_FLAGS="$cflags" \
  -DCMAKE_EXE_LINKER_FLAGS="$ldflags" \
  -DCMAKE_SHARED_LINKER_FLAGS="$ldflags" \
  -DCMAKE_C_FLAGS_RELEASE=-DNDEBUG \
  -DCMAKE_CXX_FLAGS_RELEASE=-DNDEBUG \
  -DVulkanHeaders_DIR="$HDR/share/cmake/VulkanHeaders" \
  -DUSE_GAS=OFF -DUSE_MASM=OFF -DBUILD_DLL_VERSIONINFO=1.4.363.0 \
  -DBUILD_TESTS=OFF -DLOADER_CODEGEN=OFF -DUPDATE_DEPS=OFF
cmake --build "$BL_EC" --target vulkan -j 4

# Build x64 vulkaninfo.exe for guest WoW64/Prism verification
BT_X64="$WORK/build-x64-tools"
rm -rf "$BT_X64"
cmake -S "$SRC/Vulkan-Tools" -B "$BT_X64" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$SCRIPTS/cmake-x86_64.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$cflags" \
  -DCMAKE_CXX_FLAGS="$cflags" \
  -DCMAKE_EXE_LINKER_FLAGS="$ldflags" \
  -DCMAKE_SHARED_LINKER_FLAGS="$ldflags" \
  -DCMAKE_C_FLAGS_RELEASE=-DNDEBUG \
  -DCMAKE_CXX_FLAGS_RELEASE=-DNDEBUG \
  -DVulkanHeaders_DIR="$HDR/share/cmake/VulkanHeaders" \
  -DVULKANINFO_BUILD_DLL_VERSIONINFO=1.4.363.0 \
  -DBUILD_CUBE=OFF -DBUILD_ICD=OFF -DBUILD_TESTS=OFF -DBUILD_VULKANINFO=ON \
  -DUPDATE_DEPS=OFF
cmake --build "$BT_X64" --target vulkaninfo -j 4

# Compile minimal MinGW ctor/dtor stubs for lld-link -machine:arm64x
mkdir -p "$WORK/arm64x_out"
aarch64-w64-mingw32-clang -O2 -c "$SCRIPTS/ctors.c" -o "$WORK/ctors_a64.o"
arm64ec-w64-mingw32-clang -O2 -c "$SCRIPTS/ctors.c" -o "$WORK/ctors_ec.o"

# Link ARM64X vulkan-1.dll combining build-arm64-loader + build-arm64ec-loader
BL_A64="$WORK/build-arm64-loader"
DEF="$SRC/Vulkan-Loader/loader/vulkan-1.def"
OUT_X="$WORK/arm64x_out"

lld-link -machine:arm64x -dll -entry:DllMainCRTStartup \
  -def:"$DEF" -defarm64native:"$DEF" \
  -out:"$OUT_X/vulkan-1.dll" \
  -implib:"$OUT_X/vulkan-1.lib" \
  -opt:ref -opt:icf -nxcompat -dynamicbase \
  "$LIBDIR/dllcrt2.o" "$WORK/ctors_a64.o" "$WORK/ctors_ec.o" \
  "$BL_A64"/loader/CMakeFiles/vulkan.dir/*.obj \
  "$BL_EC"/loader/CMakeFiles/vulkan.dir/*.obj \
  "$BL_A64/loader/CMakeFiles/vulkan.dir/loader.rc.res" \
  "$LIBDIR/libcfgmgr32.a" \
  "$LIBDIR/libmingw32.a" "$LIBDIR/libmingwex.a" "$LIBDIR/libmsvcrt.a" \
  "$LIBDIR/libkernel32.a" "$LIBDIR/libuser32.a" "$LIBDIR/libgdi32.a" \
  "$LIBDIR/libwinspool.a" "$LIBDIR/libshell32.a" "$LIBDIR/libole32.a" \
  "$LIBDIR/liboleaut32.a" "$LIBDIR/libuuid.a" "$LIBDIR/libcomdlg32.a" \
  "$LIBDIR/libadvapi32.a" "$LIBDIR/libmoldname.a" "$RT"

# Install unstripped ARM64X loader (do not run llvm-strip on ARM64X hybrid DLLs)
mkdir -p "$ROOT/out/vulkan-sdk/arm64" "$ROOT/out/vulkan-sdk/x64"
cp -f "$OUT_X/vulkan-1.dll" "$ROOT/out/vulkan-sdk/arm64/vulkan-1.dll"
cp -f "$BT_X64/vulkaninfo/vulkaninfo.exe" "$ROOT/out/vulkan-sdk/x64/vulkaninfo_x64.exe"
ls -lh "$ROOT/out/vulkan-sdk/arm64/vulkan-1.dll" "$ROOT/out/vulkan-sdk/x64/vulkaninfo_x64.exe"
