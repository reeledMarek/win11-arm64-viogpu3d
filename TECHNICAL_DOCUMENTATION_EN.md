# Technical Documentation: Windows 11 ARM64 3D Graphics on Raspberry Pi 5 (QEMU / Venus / Yttrium WDDM / Mesa)

This document explains the system architecture, root causes of every host/guest compatibility issue encountered, and the exact fixes implemented across `bvm`, QEMU parameters, `virtio-win-mesa`, and `yttrium-virtio-gpu`.

---

## 1. End-to-End Graphics Architecture

```text
Windows App (ARM64, x86 WoW64, or x64 via Prism/ARM64EC)
  ├── OpenGL (e.g., Java/LWJGL Minecraft) ──▶ opengl32.dll ──▶ viogpu_wgl_arm64.dll (ARM64X) / _x86.dll (Zink -> Venus)
  ├── D3D10 / D3D11 (e.g., DWM, DXGI)     ──▶ d3d11.dll    ──▶ viogpu_d3d10_arm64.dll (ARM64X) / _x86.dll (Yttrium Gallium -> Venus)
  └── Vulkan 1.3                          ──▶ vulkan-1.dll ──▶ libvulkan_virtio_arm64.dll (ARM64X) / _x86.dll (Venus ICD)
                                                                       │
                                                       D3DKMT / WDDM Escape + VirtIO DMA
                                                                       ▼
                                                            viogpu3d.sys (ARM64 KMD)
                                                                       │
                                                       QEMU virtio-gpu-gl-pci (blob=on,venus=on)
                                                       + memory-backend-memfd (share=on)
                                                                       ▼
                                                       virgl_render_server (Linux host Venus)
                                                                       │
                                                                       ▼
                                                       Mesa V3DV Vulkan (Raspberry Pi 5 VideoCore VII V3D 7.1.10.2)
```

---

## 2. Host & Hypervisor Engineering Notes (`bvm` + QEMU 10.0.13)

### 2.1 Shared `memfd` Guest RAM & Disabling `virtio-balloon` (`boot-3d`)
VirtIO-GPU `blob=on,venus=on` exports guest memory regions to `virgl_render_server` as Linux `memfd` file descriptors (`DMABUF`/memory objects). Without `-object memory-backend-memfd,id=mem1,size=${vm_mem}G,share=on`, QEMU cannot share guest backing memory with `virgl_render_server`.  
Dynamic ballooning (`-device virtio-balloon` + `bvm`'s `balloon_popper` loop) is disabled in `boot-3d` because dynamic guest page inflation/deflation conflicts with pinned Venus blob memory slots.

### 2.2 Audio Deadlock Avoidance (`pa` vs `pipewire`)
In QEMU `10.0.13` under `boot-3d` GTK GL mode, QEMU's native `pipewire` audio backend can deadlock QEMU's Big QEMU Lock (BQL) on `pw_thread_loop_lock`. Reordering `bvm` to prefer the `pa` (`pipewire-pulse` / PulseAudio) backend before native `pipewire` eliminates this hang while preserving guest audio.

### 2.3 QEMU `10.0.13` `blob[4]` Duplicate QOM Property Bug
In QEMU `10.0.13`, `virtio-gpu-gl-pci` retains `blob[N]` QOM properties across device resets and **aborts** (`attempt to add duplicate property 'blob[4]'`, `qom/object.c:1267`) whenever either:
1. Windows performs a live PnP driver reinstall/device restart (`pnputil /add-driver ... /install`), or
2. The kernel driver calls `virtio_device_reset()` during a WDDM timeout recovery (`ResetFromTimeout`), or
3. Windows undergoes an automatic reboot triggered by a bugcheck without exiting QEMU.

**Solution across both layers:**
- In KMD `ResetFromTimeout()`: drain KMD DMA/fence state safely without calling `virtio_device_reset()`.
- In deployment: stage driver updates into `DriverStore` (`pnputil /add-driver` without `/install`), update service `ImagePath` keys, and perform a clean **cold shutdown** (`shutdown /s /t 0`) followed by a fresh QEMU start (`bvm boot-3d`).

### 2.4 KVM Slot Stress Verification
Earlier host/guest diagnostics verified whether host V3D + KVM could hit slot exhaustion (448 KVM slot limit). Using `tests/slot_stress.cpp` (`50` concurrent OpenGL contexts/windows and up to `600` D3D11 staging textures), the `boot-3d` `memfd` path passed without slot exhaustion (`510` slots verified, `EXIT=0`).

---

## 3. Mesa (`virtio-win-mesa`) Engineering Fixes for Raspberry Pi 5 V3DV

### 3.1 Built-in OpenGL 3.3 Core & `GL_ARB_depth_buffer_float` Override on V3D (`wgl.c`)
- **Problem:** Minecraft `26.3` (`GlDevice.<init>`) creates an **OpenGL 3.3 Core Profile Forward-Compatible** context and allocates `GL_DEPTH_COMPONENT32F` depth textures (`GL_ARB_depth_buffer_float`). Broadcom V3DV does not advertise `VK_EXT_transform_feedback` or `VK_FORMAT_D32_SFLOAT_S8_UINT` (it supports `VK_FORMAT_D32_SFLOAT`), so Mesa Zink automatically downgraded WGL to **OpenGL 2.1** and omitted `GL_ARB_depth_buffer_float`.
- **Fix (`src/gallium/targets/wgl/wgl.c`):** After `zink_win32_create_screen(luid)` succeeds, inspect `screen->get_name(screen)`. When `"V3D"` is matched, call `os_set_option(..., false)` for:
  - `MESA_EXTENSION_OVERRIDE = "+GL_ARB_depth_buffer_float"`
  - `MESA_GL_VERSION_OVERRIDE = "3.3"`
  - `MESA_GLSL_VERSION_OVERRIDE = "330"`
  Passing `override = false` ensures any user-supplied environment variables still win, while out-of-the-box apps (Minecraft, LWJGL, SDL3) obtain GL 3.3 Core FC and complete `GL_DEPTH_COMPONENT32F` FBOs without any user configuration or modified `.jar` files.

### 3.2 D3D11 Feature Level 11_1 Avoidance (`Adapter.cpp`)
- **Problem:** Enabling Feature Level `11_1` (`D3D10UMD_YTTRIUM_ENABLE_FL11_1 = true`) advertises Target-Independent Rasterization (TIR) / features incompatible with V3DV (which also lacks `tessellationShader`), causing repeated DWM device-loss loops.
- **Fix:** Default `D3D10UMD_YTTRIUM_ENABLE_FL11_1` to `false` (leaving stable D3D11 Feature Level `11_0` / `0xb000`).

### 3.3 V3DV Venus Resource & Memory Compatibility (`yttrium_venus2_resource.c`)
1. **Display memory type selection (`yttrium_venus_choose_display_memory_type`):**  
   Broadcom V3D's unified memory heap exposes `HOST_VISIBLE | HOST_COHERENT` without `HOST_CACHED_BIT`. Requiring `HOST_CACHED_BIT` for `cpu_readback` display images failed allocation on V3DV. The helper tries `HOST_VISIBLE | HOST_CACHED` first and falls back to `HOST_VISIBLE` (preferring `HOST_COHERENT`).
2. **Linear transfer fallback (`yttrium_venus_create_shared_public_image`):**  
   V3DV rejects `VK_IMAGE_USAGE_SAMPLED_BIT` on certain linear/modifier external images (`VK_ERROR_FORMAT_NOT_SUPPORTED`). Shared public display targets only need `TRANSFER_SRC | TRANSFER_DST`; falling back to transfer-only usage allows shared D3D11/DWM swapchains to succeed.
3. **Explicit DRM UIF `rowPitch` alignment (`yttrium_venus_ensure_explicit_export_image`):**  
   For small `DRM_FORMAT_MOD_BROADCOM_UIF` images, V3DV can return a `rowPitch` from modifier-list creation that V3DV later rejects on explicit-modifier import with `VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT`. Probing explicit creation at export time and aligning single-plane `rowPitch` in 32-byte steps up to 256 prevents import failure.

### 3.4 Adapter Enumeration Fallback (`vn_renderer_d3dkmt.c`)
- **Problem:** `GetDC(NULL)` -> `D3DKMTOpenAdapterFromHdc` can fail when a process lacks primary display DC access (e.g., Session 0 or non-windowed context).
- **Fix:** Dynamically load `D3DKMTEnumAdapters2` and `D3DKMTEnumAdapters` and fall back to scanning adapters via `KMTQAITYPE_UMDRIVERPRIVATE` (`VIOGPU_IAM`). Note that actual GPU presentation / SwapChain / WGL window rendering inside Windows still requires interactive **Session 1** (DWM desktop session).

### 3.5 ARM64EC Compilation & ARM64X Hybrid Linking
To let emulated x64 Windows processes load 3D UMDs and `vulkan-1.dll` on Windows 11 ARM64:
- **Source fixes for `arm64ec-w64-mingw32-clang`:**
  - `detect_arch.h`: treat `__arm64ec__` / `_M_ARM64EC` as `DETECT_ARCH_AARCH64` + `DETECT_ARCH_ARM64EC`, never `DETECT_ARCH_X86_64`.
  - `d3d10umd/Debug.cpp` & `Resource.cpp`: avoid x86 `int3` inline asm and `<emmintrin.h>` SSE2 intrinsics under `__arm64ec__`.
  - `yttrium_context.c`: use `p_atomic_inc_return()` instead of `InterlockedIncrement64()`.
  - `vk_dispatch_table_gen.py` & `vk_entrypoints_gen.py`: emit ARM64EC `/alternatename` linker directives (`.section .drectve,"yn"`) targeting `vk_entrypoint_stub` (`weak` symbols behave differently on PE/COFF ARM64EC).
- **Linking (`scripts/link_arm64x.py`, `scripts/build_vulkan_arm64x.sh`):**
  - Invokes `lld-link -machine:arm64x -dll` combining native `aarch64` objects + `arm64ec` objects + `-def:` / `-defarm64native:` + `ctors.c` stubs.
  - Installed **unstripped** (`llvm-strip` is skipped for ARM64X to avoid stripping `CHPEMetadataPointer` tables).

---

## 4. Yttrium WDDM Kernel-Mode Driver (`viogpu3d.sys`) TDR Recovery

### 4.1 Diagnosed Crash Mechanism (`0x116 VIDEO_TDR_FAILURE`)
Prior crash dumps (`WATCHDOG-*.dmp`) captured during heavy OpenGL shaders / world loading showed Windows `dxgkrnl` hitting the default 2-second timeout (`TdrDelay=2`) and invoking:
- `VioGpu3DDdiCollectDbgInfo`
- `VioGpu3DDdiResetFromTimeout`
- `VioGpu3DDdiRestartFromTimeout`

All three DDIs previously returned `STATUS_NOT_SUPPORTED` (`0xC00000BB`), forcing Windows into immediate bugcheck `0x116 (VIDEO_TDR_FAILURE)`, an automatic guest reboot, and a cascading QEMU `blob[4]` abort.

### 4.2 Implemented Safe Recovery
1. **`viogpu_dma_retirement.h`:** Added `unsigned RetiredByReset;` so DMA retirement descriptors can outlive a TDR cleanly.
2. **`viogpu_adapter.cpp` (`ResetFromTimeout` / `ResetFromTimeoutSync`):**
   - Synchronized via `ExecuteSynchronized()` at DIRQL.
   - Walks every `m_dmaRetirement[node][engine]` queue, detaches pending entries, sets `Failed = 1` and `RetiredByReset = 1`, pushes held virtio command buffers to DPC freeing via `CtrlStagePushFromIsr()`, zeroes preemption/notified fence counters, and queues the adapter DPC.
   - **Never calls `virtio_device_reset()`**, keeping QEMU's VirtIO-GPU-GL / Venus device and host blobs intact.
3. **`InterruptRoutine()`:** Checks `cmd->Retirement.RetiredByReset` on late-arriving host completions and stages buffers directly for DPC release without advancing post-reset fence counters.
4. **`driver.cpp` & `viogpu3d_arm64_wow64.inx`:** Wires all three DDIs to return `STATUS_SUCCESS` and sets `TdrDelay = 15`, `TdrDdiDelay = 15`.

---

## 5. Observed Verification Results (Boot 9)

All verification ran against the exact packaged binaries in `out/package-arm64/` with zero `MESA_*`/`ZINK_*` environment variables and unmodified game `.jar` files:

- **Kernel driver & registry state:** `viogpu3d` `State=Running`, `Status=OK`, loaded `viogpu3d.sys` SHA256 `252DAB382C2EC660446CAB8ED0547ACABB387D7B22965336D954C2BE51CD6FAD`, `TdrDelay=15`, `TdrDdiDelay=15`, `Volume - C: is NOT Dirty`.
- **Multi-architecture `gl_d3d_probe` (`arm64`, `x86`, `x64`):**
  - `DXGI[0]: Yttrium VirtIO GPU 3D controller`
  - `D3D11 HW : OK (feature level 0xb000)`
  - `GL_RENDERER : zink Vulkan 1.3(Virtio-GPU Venus (V3D 7.1.10.2) (MESA_VENUS))`
  - `GL_VERSION : 3.3 (Compatibility Profile) Mesa 26.1.0 (git-76c095bbbd)`
  - `OpenGL draw : OK (err=0x0)`
- **Multi-architecture `vulkaninfo --summary` (`arm64`, `x86`, `x64`):**
  - `Vulkan Instance Version: 1.4.363`
  - `GPU0: Virtio-GPU Venus (V3D 7.1.10.2)` (`apiVersion 1.3.0`), `EXIT=0`.
- **Minecraft OpenGL & Depth Probes (`x64`):**
  - `test_mc_gl2_x64.exe`: `3.3_core` & `3.3_core_fc` -> `err='OK'`, `GL_VERSION='3.3 (Core Profile) Mesa 26.1.0 (git-76c095bbbd)'`.
  - `test_depth32f_x64.exe`: `glTexImage2D(GL_DEPTH_COMPONENT32F) err=0x0`, `glTexImage2D(GL_RGBA8) err=0x0`, `FBO status=0x8cd5 (0x8CD5=COMPLETE) err=0x0`.
  - `slot_stress_x64.exe`: `EXIT=0` (510+ slots).
  - `d3d_pixel_test_x64.exe`: `D3D11CreateDeviceAndSwapChain hr=0x00000000 fl=0xb000`, `D3D11 Present hr=0x00000000` (rendered green swapchain output); `D3D9Ex CreateDeviceEx(HWVP)` returned `0x8007000e` (expected: `viogpu_d3d10` has no D3D9 UMD).
- **Real Application Test (Unmodified TLauncher 2.9382 -> Minecraft 26.3):**
  - `TLauncher.jar` (`SHA1=502594e4ed7d40efc48d827aee166fd86d8006dc`) and `26.3.jar` (`SHA1=e877b6a07acd633fb3bb475002175cec036e7b87`) verified unmodified.
  - `.minecraft/logs/latest.log`: initialized `3.3 (Core Profile) Mesa 26.1.0 (git-76c095bbbd)` on `zink Vulkan 1.3(Virtio-GPU Venus (V3D 7.1.10.2) (MESA_VENUS))`.
  - Created and loaded Singleplayer world `New World (1)` (`Time elapsed: 222461 ms`) into live 3D rendering (`javaw` & `dwm` `Responding=True`, zero `WATCHDOG` dumps or Event Log `4101` TDR resets).
