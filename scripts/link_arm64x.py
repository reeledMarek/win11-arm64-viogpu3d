#!/usr/bin/env python3
"""Link ARM64 + ARM64EC Mesa/Vulkan build artifacts into ARM64X hybrid DLLs via lld-link."""
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
LLD_LINK = ROOT / "toolchain/llvm-mingw/bin/lld-link"
A64_CC = ROOT / "toolchain/llvm-mingw/bin/aarch64-w64-mingw32-clang"
EC_CC = ROOT / "toolchain/llvm-mingw/bin/arm64ec-w64-mingw32-clang"
LIBDIR = ROOT / "toolchain/llvm-mingw/aarch64-w64-mingw32/lib"
RT_LIB = ROOT / "toolchain/llvm-mingw/lib/clang/23/lib/windows/libclang_rt.builtins-aarch64.a"

A64 = ROOT / "obj-mesa/build-arm64"
EC = ROOT / "obj-mesa/build-arm64ec"
OUT_X = ROOT / "obj-mesa/arm64x_out"
OUT_MESA_ARM64 = ROOT / "out/mesa/arm64"
OUT_X.mkdir(parents=True, exist_ok=True)
OUT_MESA_ARM64.mkdir(parents=True, exist_ok=True)


def ensure_ctors() -> tuple[pathlib.Path, pathlib.Path]:
    ctors_c = SCRIPTS / "ctors.c"
    c_a64 = ROOT / "obj-mesa/ctors_a64.o"
    c_ec = ROOT / "obj-mesa/ctors_ec.o"
    subprocess.run([str(A64_CC), "-O2", "-c", str(ctors_c), "-o", str(c_a64)], check=True)
    subprocess.run([str(EC_CC), "-O2", "-c", str(ctors_c), "-o", str(c_ec)], check=True)
    return c_a64, c_ec


def run_lld(name: str, def_rel: str, objs: list[pathlib.Path], whole: list[str], libs: list[str], extra_sys: list[str]) -> None:
    def_file = A64 / def_rel
    out_dll = OUT_X / name
    c_a64, c_ec = ensure_ctors()
    cmd = [
        str(LLD_LINK),
        "-machine:arm64x",
        "-dll",
        "-entry:DllMainCRTStartup",
        f"-def:{def_file}",
        f"-defarm64native:{def_file}",
        f"-out:{out_dll}",
        f"-implib:{OUT_X / (name + '.lib')}",
        "-opt:ref",
        "-opt:icf",
        "-nxcompat",
        "-dynamicbase",
        str(LIBDIR / "dllcrt2.o"),
        str(c_a64),
        str(c_ec),
    ]
    cmd.extend(str(o) for o in objs)
    for w in whole:
        cmd.append(f"-wholearchive:{A64 / w}")
        cmd.append(f"-wholearchive:{EC / w}")
    for l in libs:
        cmd.append(str(A64 / l))
        cmd.append(str(EC / l))
    sys_libs = extra_sys + [
        "libc++.a", "libmingw32.a", "libmingwex.a", "libmsvcrt.a",
        "libm.a", "libsynchronization.a", "libkernel32.a", "libuser32.a",
        "libgdi32.a", "libwinspool.a", "libshell32.a", "libole32.a",
        "liboleaut32.a", "libuuid.a", "libcomdlg32.a", "libadvapi32.a",
        "libunwind.a", "libmoldname.a",
    ]
    for sl in sys_libs:
        cmd.append(str(LIBDIR / sl))
    cmd.append(str(RT_LIB))
    print(f"=== Linking {name} (ARM64X) ===")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.stdout:
        print(res.stdout)
    if res.stderr:
        print(res.stderr, file=sys.stderr)
    if res.returncode != 0:
        sys.exit(f"lld-link failed for {name}: rc={res.returncode}")
    print(f"OK: {out_dll} ({out_dll.stat().st_size} bytes)")
    dst = OUT_MESA_ARM64 / name
    shutil.copy2(out_dll, dst)
    print(f"Installed unstripped ARM64X DLL -> {dst}")


def main() -> None:
    targets = sys.argv[1:] or ["libvulkan_virtio.dll", "viogpu_d3d10.dll", "viogpu_wgl.dll"]

    if "libvulkan_virtio.dll" in targets:
        objs = sorted((A64 / "src/virtio/vulkan/libvulkan_virtio.dll.p").glob("*.obj")) + \
               sorted((EC / "src/virtio/vulkan/libvulkan_virtio.dll.p").glob("*.obj"))
        run_lld(
            "libvulkan_virtio.dll",
            "src/vulkan/vulkan_api.def",
            objs,
            [
                "src/vulkan/runtime/libvulkan_lite_runtime.a",
                "src/vulkan/runtime/libvulkan_lite_instance.a",
                "src/vulkan/wsi/libvulkan_wsi.a",
            ],
            [
                "src/util/libmesa_util.a",
                "src/util/libmesa_util_simd.a",
                "src/util/blake3/libblake3.a",
                "src/c11/impl/libmesa_util_c11.a",
                "src/vulkan/util/libvulkan_util.a",
                "src/util/libxmlconfig.a",
                "subprojects/DirectX-Headers-1.0/libd3dx12-format-properties.a",
                "subprojects/DirectX-Headers-1.0/libDirectX-Guids.a",
            ],
            [],
        )

    if "viogpu_d3d10.dll" in targets:
        objs = sorted((A64 / "src/gallium/targets/d3d10umd/viogpu_d3d10.dll.p").glob("*.obj")) + \
               sorted((EC / "src/gallium/targets/d3d10umd/viogpu_d3d10.dll.p").glob("*.obj"))
        run_lld(
            "viogpu_d3d10.dll",
            "src/gallium/targets/d3d10umd/d3d10.def",
            objs,
            [
                "src/gallium/frontends/d3d10umd/libd3d10umd.a",
            ],
            [
                "src/gallium/auxiliary/libgallium.a",
                "src/compiler/nir/libnir.a",
                "src/compiler/libcompiler.a",
                "src/util/libmesa_util.a",
                "src/util/libmesa_util_simd.a",
                "src/util/blake3/libblake3.a",
                "src/c11/impl/libmesa_util_c11.a",
                "src/gallium/auxiliary/libgalliumvl.a",
                "src/gallium/winsys/sw/gdi/libwsgdi.a",
                "src/gallium/winsys/yttrium/gdi/libyttriumgdi.a",
            ],
            ["libws2_32.a"],
        )

    if "viogpu_wgl.dll" in targets:
        objs = sorted((A64 / "src/gallium/targets/wgl/viogpu_wgl.dll.p").glob("*.obj")) + \
               sorted((EC / "src/gallium/targets/wgl/viogpu_wgl.dll.p").glob("*.obj"))
        run_lld(
            "viogpu_wgl.dll",
            "src/gallium/targets/wgl/gallium_wgl.def",
            objs,
            [
                "src/gallium/frontends/wgl/libwgl.a",
            ],
            [
                "src/gallium/auxiliary/libgallium.a",
                "src/compiler/nir/libnir.a",
                "src/compiler/libcompiler.a",
                "src/util/libmesa_util.a",
                "src/util/libmesa_util_simd.a",
                "src/util/blake3/libblake3.a",
                "src/c11/impl/libmesa_util_c11.a",
                "src/compiler/glsl/libglsl.a",
                "src/compiler/glsl/glcpp/libglcpp.a",
                "src/mesa/libmesa.a",
                "src/compiler/spirv/libvtn.a",
                "src/gallium/winsys/sw/gdi/libwsgdi.a",
                "src/mesa/glapi/glapi/libglapi_bridge.a",
                "src/mesa/glapi/shared-glapi/libglapi.a",
                "src/gallium/auxiliary/libgalliumvl_stub.a",
                "src/gallium/drivers/zink/libzink.a",
                "src/vulkan/util/libvulkan_util.a",
                "src/util/libxmlconfig.a",
            ],
            ["libws2_32.a"],
        )


if __name__ == "__main__":
    main()
