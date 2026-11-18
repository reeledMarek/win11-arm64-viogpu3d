#!/usr/bin/env bash
# Cross-compile Yttrium viogpu3d.sys + helpers (viogpuap.exe, vgpusrv.exe) for Windows 11 ARM64.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src/yttrium-virtio-gpu"
TOOLCHAIN="$ROOT/toolchain/llvm-mingw"
WDK="$ROOT/toolchain/wdk-arm64"
SDK="$ROOT/toolchain/sdk-cpp"
OBJ="$ROOT/obj-kmd-arm64"
OUT="$ROOT/out/kmd-arm64"
SCRIPTS="$ROOT/scripts"

KITVER=10.0.26100.0
WINC="$WDK/c/Include/$KITVER"
SINC="$SDK/c/Include/$KITVER"
KMLIB="$WDK/c/Lib/$KITVER/km/ARM64"

CLANG="$TOOLCHAIN/bin/clang"
LLD_LINK="$TOOLCHAIN/bin/lld-link"
LLVM_LIB="$TOOLCHAIN/bin/llvm-lib"
LLVM_RC="$TOOLCHAIN/bin/llvm-rc"
CXX="$TOOLCHAIN/bin/aarch64-w64-mingw32-clang++"

DRIVER_VERSION=${KMD_DRIVER_VERSION:-100.6.101.58104}
IFS=. read -r V1 V2 V3 V4 <<<"$DRIVER_VERSION"

CLANG_RES=$("$CLANG" -print-resource-dir)
rm -rf "$OBJ" "$OUT"
mkdir -p "$OBJ/virtiolib" "$OBJ/viogpu3d" "$OBJ/gen" "$OBJ/helpers/inc" "$OUT"

for f in driver viogpu_queue viogpu_pci bitops viogpu_idr VirtIOPCILegacy VirtIOPCIModern; do
    printf '// generated: WPP disabled in Linux cross-build\n' >"$OBJ/gen/$f.tmh"
done
cat >>"$OBJ/gen/driver.tmh" <<'EOF'
#define WPP_INIT_TRACING(DriverObject, RegistryPath) do { UNREFERENCED_PARAMETER(DriverObject); UNREFERENCED_PARAMETER(RegistryPath); } while (0)
#define WPP_CLEANUP(DriverObject) do { UNREFERENCED_PARAMETER(DriverObject); } while (0)
EOF

python3 "$SCRIPTS/mkoverlay.py" "$OBJ/overlay.json" \
    "$WINC/km" "$WINC/shared" "$SINC/shared" "$SINC/um" "$SRC/VirtIO" "$SRC/viogpu" "$OBJ/gen"

CLFLAGS=(
    --driver-mode=cl --target=aarch64-pc-windows-msvc -fms-compatibility-version=19.44
    /nologo /c /X /kernel /GS /Gy /Zp8 /GR- /Zc:wchar_t- /EHs-c- /O2 /Oi /Z7 /W3
    /Brepro -vfsoverlay "$OBJ/overlay.json"
    -Wno-nonportable-include-path -Wno-microsoft-include -Wno-pragma-pack
    -Wno-unknown-pragmas -Wno-ignored-pragma-intrinsic -Wno-microsoft-anon-tag
    -Wno-error=incompatible-function-pointer-types
    /I"$OBJ/gen"
    -imsvc "$CLANG_RES/include"
    -imsvc "$WINC/km/crt" -imsvc "$WINC/km" -imsvc "$SINC/shared" -imsvc "$WINC/shared" -imsvc "$SINC/um"
    /FI"$SINC/shared/warning.h" /FIintrin.h
    /D_WIN64 /D_ARM64_ /DARM64 /DDEPRECATE_DDK_FUNCTIONS=1 /DMSC_NOOPT
    /D_WIN32_WINNT=0x0A00 /DWINVER=0x0A00 /DWINNT=1 /DNTDDI_VERSION=0x0A000010
    /DVENDOR_VER=RHEL.ver /DVER_OS=Win11 /DVER_ARCH=ARM64 /DCOPYRIGHT_CURRENT_YEAR=2026
    /D_NT_TARGET_MAJ=$V1 /D_RHEL_RELEASE_VERSION_=$V2 /D_BUILD_MAJOR_VERSION_=$V3
    /D_BUILD_MINOR_VERSION_=$V4 "/DRHEL_COPYRIGHT_STARTING_YEAR=20??"
)

cc() {
    local objdir=$1 src=$2; shift 2
    local o="$objdir/$(basename "${src%.*}").obj"
    echo "  CC $src"
    "$CLANG" "${CLFLAGS[@]}" "$@" "$src" /Fo"$o"
}

echo "== VirtioLib (ARM64)"
for f in VirtIOPCICommon.c VirtIOPCILegacy.c VirtIOPCIModern.c VirtIORing-Packed.c VirtIORing.c; do
    cc "$OBJ/virtiolib" "$SRC/VirtIO/$f" /I"$SRC/VirtIO"
done
"$LLVM_LIB" /nologo /out:"$OBJ/virtiolib.lib" "$OBJ"/virtiolib/*.obj

echo "== viogpu3d (ARM64)"
GPU_INC=(/I"$SRC/viogpu/common" /I"$SRC/viogpu/shared" /I"$SRC/VirtIO" /I"$SRC/viogpu/viogpu3d"
         /DVIOGPU_3D=1 /std:c++17)
for f in common/edid.cpp common/viogpu_idr.cpp common/viogpu_pci.cpp common/viogpu_queue.cpp \
         viogpu3d/driver.cpp viogpu3d/viogpu_command.cpp viogpu3d/viogpu_device.cpp \
         viogpu3d/viogpu_allocation.cpp viogpu3d/viogpu_adapter.cpp \
         viogpu3d/viogpu_blob_user_view.cpp \
         viogpu3d/viogpu_shmem_allocator.cpp common/baseobj.cpp common/bitops.cpp \
         viogpu3d/viogpu_vidpn.cpp; do
    cc "$OBJ/viogpu3d" "$SRC/viogpu/$f" "${GPU_INC[@]}"
done

echo "  RC viogpu3d.rc (ARM64)"
iconv -f UTF-16 -t UTF-8 "$SRC/viogpu/viogpu3d/viogpu3d.rc" | sed 's/\r$//' >"$OBJ/gen/viogpu3d.utf8.rc"
"$CLANG" --driver-mode=cl --target=aarch64-pc-windows-msvc -fms-compatibility-version=19.44 \
    /nologo /X /EP -vfsoverlay "$OBJ/overlay.json" -Wno-nonportable-include-path -Wno-microsoft-include \
    /I"$SRC/viogpu/viogpu3d" /I"$SRC/build" \
    -imsvc "$SINC/um" -imsvc "$SINC/shared" -imsvc "$WINC/km/crt" \
    /DRC_INVOKED /D_WIN64 /D_ARM64_ /DARM64 /DNTDDI_VERSION=0x0A000010 /D_WIN32_WINNT=0x0A00 \
    /DVENDOR_VER=rhel.ver /DVER_OS=Win11 /DVER_ARCH=ARM64 \
    /D_NT_TARGET_MAJ=$V1 /D_RHEL_RELEASE_VERSION_=$V2 /D_BUILD_MAJOR_VERSION_=$V3 \
    /D_BUILD_MINOR_VERSION_=$V4 '/DRHEL_COPYRIGHT_YEARS=2026' \
    /Tc"$OBJ/gen/viogpu3d.utf8.rc" >"$OBJ/gen/viogpu3d.i.rc"
"$LLVM_RC" /nologo /no-preprocess /C 1252 /FO "$OBJ/viogpu3d.res" "$OBJ/gen/viogpu3d.i.rc"

echo "  LINK viogpu3d.sys (ARM64)"
"$LLD_LINK" /nologo /DRIVER /SUBSYSTEM:NATIVE,10.00 /ENTRY:GsDriverEntry /NODEFAULTLIB \
    /MACHINE:ARM64 /RELEASE /INCREMENTAL:NO /OPT:REF /OPT:ICF /Brepro /TSAWARE:NO \
    /MERGE:_TEXT=.text /MERGE:_PAGE=PAGE /SECTION:INIT,ERD \
    /DEBUG /PDB:"$OUT/viogpu3d.pdb" /PDBALTPATH:viogpu3d.pdb \
    /OUT:"$OUT/viogpu3d.sys" \
    "$OBJ"/viogpu3d/*.obj "$OBJ/viogpu3d.res" "$OBJ/virtiolib.lib" \
    "$KMLIB/bufferoverflowfastfailk.lib" "$KMLIB/ntoskrnl.lib" "$KMLIB/hal.lib" \
    "$KMLIB/wmilib.lib" "$KMLIB/displib.lib" "$KMLIB/libcntpr.lib"

echo "== helpers (ARM64)"
for h in d3dkmthk.h d3dukmdt.h d3dkmdt.h; do
    cp "$SINC/shared/$h" "$OBJ/helpers/inc/" 2>/dev/null || cp "$SINC/um/$h" "$OBJ/helpers/inc/"
done
python3 "$SCRIPTS/mkoverlay.py" "$OBJ/helpers/overlay.json" "$SRC/viogpu" "$OBJ/helpers/inc" \
    "$TOOLCHAIN/aarch64-w64-mingw32/include"

CXXFLAGS=(
    -O2 -std=c++17 -municode -DUNICODE -D_UNICODE -DNDEBUG -D_CONSOLE
    -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 -DNTDDI_VERSION=0x0A000010
    -fms-extensions -ivfsoverlay "$OBJ/helpers/overlay.json" -Wno-nonportable-include-path
    -idirafter "$OBJ/helpers/inc" -include "$SCRIPTS/mingw-compat.h"
    -ffile-prefix-map="$SRC"=. -Wl,--no-insert-timestamp
    -static -s
)

echo "  CXX viogpuap.exe"
"$CXX" "${CXXFLAGS[@]}" -I"$SRC/viogpu/viogpuap" -I"$SRC/viogpu/shared" \
    "$SRC"/viogpu/viogpuap/{GpuAdapter,GpuAdaptersMgr,pch,viogpuap}.cpp \
    "$SRC"/viogpu/shared/{log,pipe}.cpp \
    -o "$OUT/viogpuap.exe" -lcfgmgr32 -lgdi32 -luser32 -ladvapi32 -lshell32 -lole32 -luuid

echo "  CXX vgpusrv.exe"
"$CXX" "${CXXFLAGS[@]}" -I"$SRC/viogpu/viogpusc" -I"$SRC/viogpu/shared" \
    "$SRC"/viogpu/viogpusc/{pch,Service,Session,SessionMgr,utils,viogpusc}.cpp \
    "$SRC"/viogpu/shared/{log,pipe}.cpp \
    -o "$OUT/vgpusrv.exe" -lwtsapi32 -luserenv -ladvapi32 -luser32 -lgdi32 -lshell32 -lole32

ls -lh "$OUT"
file "$OUT/viogpu3d.sys" "$OUT/viogpuap.exe" "$OUT/vgpusrv.exe"
