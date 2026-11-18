# Windows 11 ARM64 3D Graphics Drivers on Raspberry Pi 5 (BVM / QEMU / Venus / Mesa / Yttrium WDDM)

Hardware-accelerated 3D graphics stack for **Windows 11 ARM64** running inside **QEMU/KVM** on **Raspberry Pi 5 (Broadcom VideoCore VII / V3D)** via **VirtIO-GPU Venus** (`virgl_render_server`), adapted **Yttrium WDDM Kernel-Mode Driver (`viogpu3d.sys`)**, and **ARM64X + x86 User-Mode Drivers** (`viogpu_wgl`, `viogpu_d3d10`, `libvulkan_virtio`, and Khronos `vulkan-1.dll`).

Designed and verified to run standard Windows 3D applications and emulated x64 OpenGL/Vulkan games (including **unmodified TLauncher & Minecraft 26.3**) using standard WGL/OpenGL 3.3 Core, Vulkan 1.3, and D3D11 calls—without modifying any game binaries or setting manual `MESA_*` environment overrides.

---

## Verified Target Stack & Capabilities

| Layer | Component | Verified Version / Behavior |
|---|---|---|
| **Host OS / Kernel** | Debian GNU/Linux (`aarch64`, Raspberry Pi 5) | Linux `6.18.60+rpt-rpi-v8` |
| **Host GPU / Renderer** | VideoCore VII + `virgl_render_server` | `V3D 7.1.10.2` (Mesa V3DV Vulkan) |
| **Hypervisor** | QEMU `10.0.13` + patched `bvm boot-3d` | `virtio-gpu-gl-pci` (`blob=on,venus=on`) + `memory-backend-memfd` |
| **Guest OS** | Windows 11 Pro ARM64 | Build `26300` (`10.0.26300`) |
| **Kernel Driver (KMD)** | Patched Yttrium `viogpu3d.sys` | WDDM TDR `ResetFromTimeout` recovery + `TdrDelay=15` |
| **D3D10/11 UMD** | `viogpu_d3d10` (ARM64X + x86) | Hardware D3D11 Feature Level `0xb000` (FL 11_0) |
| **OpenGL UMD** | `viogpu_wgl` / Zink (ARM64X + x86) | OpenGL `3.3 (Core & Compat)` Mesa `26.1.0` + `GL_ARB_depth_buffer_float` |
| **Vulkan ICD + Loader** | `libvulkan_virtio` + `vulkan-1.dll` (ARM64X + x86) | Vulkan `1.3.0` (`Virtio-GPU Venus (V3D 7.1.10.2)`), Loader `1.4.363.0` |

### Why ARM64X Hybrid DLLs?
Windows 11 ARM64 runs x64 applications (such as x64 `javaw.exe` launched by TLauncher) through Prism/ARM64EC emulation. Emulated x64 processes cannot load pure `aarch64` DLLs directly; they require **ARM64X hybrid DLLs** (`aarch64` + `arm64ec` CHPEv2 code inside one DLL). This kit links `viogpu_wgl_arm64.dll`, `viogpu_d3d10_arm64.dll`, `libvulkan_virtio_arm64.dll`, and `vulkan-1.dll` as ARM64X so **native ARM64, x86 (WoW64), and emulated x64** apps all share hardware 3D acceleration.

---

## Kit / Repository Contents

```text
win11-arm64-viogpu3d/
├── LICENSE                            # BSD 3-Clause License (for repository scripts, patches, tests & docs; see License section)
├── README.md                          # Project overview & quick start (English)
├── STEP_BY_STEP_DRIVER_GUIDE_EN.txt   # Complete build, patch, and install guide (English)
├── TECHNICAL_DOCUMENTATION_EN.md      # Deep technical documentation & root-cause analysis (English)
├── patches/
│   ├── bvm-boot-3d.patch              # Patch for Botspot BVM adding boot-3d, virgl-server, pa audio, NBD fixes
│   ├── bvm-config.example             # Recommended ~/win11/bvm-config settings
│   ├── virtio-win-mesa.patch          # Git diff vs upstream arehnman/virtio-win-mesa (76c095b)
│   └── yttrium-virtio-gpu.patch       # Git diff vs upstream arehnman/yttrium-virtio-gpu (e9917ae)
├── out/package-arm64/                 # Pre-built, test-signed ready-to-install Windows 11 ARM64 kit
│   ├── Install-ARM64-3D.cmd
│   ├── yttrium-test-signing.cer
│   ├── driver/                        # viogpu3d.{sys,inf,cat}, vgpusrv.exe, viogpuap.exe, arm64/ & x86/ UMDs
│   └── runtime/                       # ARM64X + x86 Khronos vulkan-1.dll & vulkaninfo.exe
├── scripts/                           # Cross-build, ARM64X linking, cert generation, packaging & safe update scripts
├── tests/                             # Multi-arch D3D11/OpenGL/Vulkan probes & stress tests
└── src/                               # Patched source trees (virtio-win-mesa, yttrium-virtio-gpu, vulkan-sdk, generate-cat-file)
```

---

## Quick Start (Pre-Built Ready-to-Install Kit)

### 1. Host Setup (Raspberry Pi 5 Linux)
1. Install `virgl-server` and ensure `/usr/libexec/virgl_render_server` is executable:
   ```bash
   sudo apt update && sudo apt install -y virgl-server
   ```
2. Patch your local `bvm` installation (`~/.local/share/bvm/bvm`):
   ```bash
   patch -d ~/.local/share/bvm -p1 < patches/bvm-boot-3d.patch
   ```
3. In your VM config (`~/win11/bvm-config`), set at least `vm_mem=8` and `disable_updates=true` (see `patches/bvm-config.example`).
4. Boot Windows 11 with Venus 3D acceleration enabled (**use CLI `boot-3d`, not the default `bvm gui` modes**, which launch 2D or RDP without `virtio-gpu-gl-pci`):
   ```bash
   bvm boot-3d ~/win11
   ```

### 2. Guest Installation (Windows 11 ARM64)
Copy `out/package-arm64/` to `C:\Yttrium-ARM64-3D\` inside Windows 11.

- **Clean first-time installation** (from Microsoft Basic Display Adapter / no live `viogpu3d` blob device active):  
  Run `C:\Yttrium-ARM64-3D\Install-ARM64-3D.cmd` **as Administrator**, then reboot Windows.
- **Updating an already active `viogpu3d` driver under QEMU 10.0.13 (`blob=on`)**:  
  **NEVER run `pnputil /add-driver ... /install` while `virtio-gpu-gl-pci` is live**—QEMU 10.0.13 aborts on warm device reset (`attempt to add duplicate property 'blob[4]'`). Instead, run `scripts/Stage-DriverUpdate-Safe.ps1` as Administrator, perform a **full cold shutdown** (`shutdown /s /t 0`), wait for QEMU to exit, and boot again with `bvm boot-3d ~/win11`.

See [`STEP_BY_STEP_DRIVER_GUIDE_EN.txt`](STEP_BY_STEP_DRIVER_GUIDE_EN.txt) for exact step-by-step details and verification commands.

---

## Building from Source

Building from `src/` requires a Linux `aarch64` (or `x86_64`) host with Meson, Ninja, CMake, Python 3, `osslsigncode`, plus the cross-compilation toolchain populated under `toolchain/`:
- `llvm-mingw` (Clang 23 + `lld-link`, release `llvm-mingw-20261006-ucrt-ubuntu-22.04-aarch64`)
- Microsoft Windows WDK ARM64 & SDK C++ NuGet packages (`10.0.26100.6584`, `KITVER=10.0.26100.0`)

From the project root:
```bash
# 1. Build generate-cat-file host tools (if not already built)
make -C src/generate-cat-file

# 2. Cross-compile Yttrium WDDM Kernel-Mode Driver + services (viogpu3d.sys, vgpusrv.exe, viogpuap.exe)
./scripts/build_kmd_arm64.sh

# 3. Prepare Winddk headers for Mesa (when bootstrapping from clean packages)
# python3 scripts/prepare-winddk.py src/virtio-win-mesa <wdk_or_sdk_nupkgs...>

# 4. Cross-compile Mesa UMDs for ARM64 & x86
./scripts/build_mesa.sh

# 5. Cross-compile Khronos Vulkan Headers, Loader & vulkaninfo for ARM64 & x86
./scripts/build_vulkan_runtime.sh

# 6. Build ARM64EC objects + link unstripped ARM64X hybrid DLLs + build x64 vulkaninfo_x64.exe
./scripts/build_arm64x.sh

# 7. Generate a local test-signing cert (skipped if you already have signing/test-signing.{crt,key})
./scripts/gen_test_cert.sh

# 8. Assemble, generate .cat catalog, and test-sign out/package-arm64/
python3 scripts/package_and_sign_arm64.py
```

---

## Known Limitations
- **Direct3D 9 (`d3d9.dll`):** `viogpu_d3d10` provides D3D10/D3D11 acceleration only (`Direct3DCreate9Ex` `CreateDeviceEx(HWVP)` returns `0x8007000e`). Apps whose launcher embeds JavaFX `prism_d3d.dll` (e.g., TLauncher's ad/info web pane `BrowserSimplePanel`) show a blank/gray middle panel while native Swing controls (`Enter the game`) and OpenGL/Vulkan/D3D11 rendering work normally.
- **`bvm gui` menu:** The upstream YAD GUI dropdown in `bvm` does not yet expose `boot-3d`; launch 3D sessions with `bvm boot-3d <vmdir>`.
- **Performance expectations on Raspberry Pi 5:** First-time world generation and shader compilation in Minecraft 26.3 take a few minutes (`222,461 ms` observed for `New World (1)` spawn generation), which is why `TdrDelay=15` and `ResetFromTimeout` recovery are essential and included.

---

## License & Upstream Attribution

### Original Scripts, Patches, Tests & Documentation (`BSD-3-Clause`)
All original scripts (`scripts/`), patches (`patches/`), verification tests (`tests/`), and documentation (`README.md`, `STEP_BY_STEP_DRIVER_GUIDE_EN.txt`, `TECHNICAL_DOCUMENTATION_EN.md`) added in this repository are licensed under the **BSD 3-Clause License** (see `LICENSE`).

### Third-Party Source Trees (`src/`) & Prebuilt Binaries (`out/package-arm64/`)
Each bundled upstream source tree under `src/` (and the corresponding binaries compiled from them in `out/package-arm64/`) remains under its own original open-source license:

- **Yttrium VirtIO-GPU Driver** — [`arehnman/yttrium-virtio-gpu`](https://github.com/arehnman/yttrium-virtio-gpu) (`src/yttrium-virtio-gpu/`, branch `yttrium-wddm2`, tag `yttrium-experimental-2026-11-02`, commit `e9917ae`): **BSD 3-Clause / BSD 2-Clause** (see `src/yttrium-virtio-gpu/LICENSE` and `src/yttrium-virtio-gpu/viogpu/LICENSE`)
- **VirtIO-Win Mesa** — [`arehnman/virtio-win-mesa`](https://github.com/arehnman/virtio-win-mesa) (`src/virtio-win-mesa/`, branch `yttrium-experimental`, commit `76c095b`): **MIT License** & component licenses (see `src/virtio-win-mesa/docs/license.rst` and `src/virtio-win-mesa/licenses/`)
- **Khronos Vulkan SDK** — [`KhronosGroup/Vulkan-{Headers,Loader,Tools}`](https://github.com/KhronosGroup) (`src/vulkan-sdk/`, tag `vulkan-sdk-1.4.363.0`): **Apache-2.0 / MIT** (see `src/vulkan-sdk/*/LICENSE*`)
- **Catalog Tool** — [`LINBIT/generate-cat-file`](https://github.com/LINBIT/generate-cat-file) (`src/generate-cat-file/`, branch `main`, commit `65ebf4d`): **GPL-2.0** (standalone host build utility executed during packaging, see `src/generate-cat-file/COPYING`)
- **BVM Patch Target** — [`Botspot/bvm`](https://github.com/Botspot/bvm) (`patches/bvm-boot-3d.patch`): standalone unified diff targeting Botspot BVM

> Note: `src/virtio-win-mesa/include/winddk/.gitignore` excludes proprietary Microsoft WDK/SDK headers from Git tracking; extract them locally from Microsoft WDK/SDK packages via `scripts/prepare-winddk.py` when rebuilding from scratch. The binaries in `out/package-arm64/` are signed using a local self-signed test certificate (`yttrium-test-signing.cer`) for Windows `testsigning` mode.
