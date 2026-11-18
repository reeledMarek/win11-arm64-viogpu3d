#!/usr/bin/env python3
"""Assemble and test-sign the Windows 11 ARM64 + WoW64 viogpu3d driver package."""
import hashlib
import os
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
INX = ROOT / "src/yttrium-virtio-gpu/viogpu/viogpu3d/viogpu3d_arm64_wow64.inx"
KMD_OUT = ROOT / "out/kmd-arm64"
MESA_OUT = ROOT / "out/mesa"
VK_OUT = ROOT / "out/vulkan-sdk"
SIGNING = ROOT / "signing"
CAT_BIN = ROOT / "src/generate-cat-file/generate-cat-file"
STRIP_PE = ROOT / "src/generate-cat-file/strip-pe-image"
PKG = ROOT / "out/package-arm64"
DRV = PKG / "driver"

DRIVER_VER = "11/17/2026, 100.6.101.58105"

DROP_TOKENS = (
    "libEGL", "libGLESv1_CM", "libGLESv2", "opengl32",
    "vulkan_lvp", "lvp_icd", "yttrium12", "TdrDebugMode", "EnablePreemption",
)


def make_inf(dst: pathlib.Path) -> None:
    lines = INX.read_text(encoding="utf-8").splitlines()
    out = []
    for line in lines:
        code = line.split(";", 1)[0]
        if any(tok in code for tok in DROP_TOKENS):
            continue
        line = line.replace("NT$ARCH$...16299", "NTARM64.10.0...16299")
        if re.match(r"^\s*DriverVer\s*=", line, re.I):
            line = f"DriverVer = {DRIVER_VER}"
        elif re.match(r"^\s*FeatureScore\s*=", line, re.I):
            line = "FeatureScore=E0"
        elif re.match(r"^\s*HKR,,\s*UserModeDriverName\s*,", line, re.I):
            line = r"HKR,, UserModeDriverName,          %REG_MULTI_SZ%, %11%\viogpu_d3d10.dll,%11%\viogpu_d3d10.dll,%11%\viogpu_d3d10.dll"
        elif re.match(r"^\s*HKR,,\s*UserModeDriverNameWow\s*,", line, re.I):
            line = r"HKR,, UserModeDriverNameWow,       %REG_MULTI_SZ%, %16425%\viogpu_d3d10.dll,%16425%\viogpu_d3d10.dll,%16425%\viogpu_d3d10.dll"
        elif "PCI\\VEN_1AF4&DEV_1050&SUBSYS_11001AF4&REV_01" in code and "VioGpu3D_Inst" in code:
            line = "%VioGpu3D.DeviceDesc% = VioGpu3D_Inst, PCI\\VEN_1AF4&DEV_1050&SUBSYS_11001AF4&REV_01, PCI\\VEN_1AF4&DEV_1050"
        out.append(line)
    dst.write_bytes(("\r\n".join(out) + "\r\n").encode("ascii"))


def sign_pe(path: pathlib.Path, crt: pathlib.Path, key: pathlib.Path, sign_time: str) -> None:
    tmp = path.with_suffix(path.suffix + ".signed")
    if tmp.exists():
        tmp.unlink()
    subprocess.run(
        [
            "osslsigncode", "sign",
            "-certs", str(crt),
            "-key", str(key),
            "-h", "sha256",
            "-time", sign_time,
            "-in", str(path),
            "-out", str(tmp),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    tmp.replace(path)


def main() -> None:
    for needed in [
        KMD_OUT / "viogpu3d.sys",
        KMD_OUT / "viogpuap.exe",
        KMD_OUT / "vgpusrv.exe",
        MESA_OUT / "arm64/viogpu_d3d10.dll",
        MESA_OUT / "arm64/viogpu_wgl.dll",
        MESA_OUT / "arm64/libvulkan_virtio.dll",
        MESA_OUT / "arm64/virtio_icd.aarch64.json",
        MESA_OUT / "x86/viogpu_d3d10.dll",
        MESA_OUT / "x86/viogpu_wgl.dll",
        MESA_OUT / "x86/libvulkan_virtio.dll",
        MESA_OUT / "x86/virtio_icd.i686.json",
        VK_OUT / "arm64/vulkan-1.dll",
        VK_OUT / "arm64/vulkaninfo.exe",
        VK_OUT / "x86/vulkan-1.dll",
        VK_OUT / "x86/vulkaninfo.exe",
    ]:
        if not needed.is_file():
            sys.exit(f"Missing build artifact: {needed}")

    if PKG.exists():
        shutil.rmtree(PKG)
    (DRV / "arm64").mkdir(parents=True, exist_ok=True)
    (DRV / "x86").mkdir(parents=True, exist_ok=True)

    for fname in ["viogpu3d.sys", "viogpuap.exe", "vgpusrv.exe"]:
        shutil.copy2(KMD_OUT / fname, DRV / fname)

    for dll in ["viogpu_d3d10", "viogpu_wgl", "libvulkan_virtio"]:
        shutil.copy2(MESA_OUT / f"arm64/{dll}.dll", DRV / f"arm64/{dll}_arm64.dll")
        shutil.copy2(MESA_OUT / f"x86/{dll}.dll", DRV / f"x86/{dll}_x86.dll")

    shutil.copy2(MESA_OUT / "arm64/virtio_icd.aarch64.json", DRV / "arm64/virtio_icd.aarch64.json")
    shutil.copy2(MESA_OUT / "x86/virtio_icd.i686.json", DRV / "x86/virtio_icd.x86.json")

    inf_path = DRV / "viogpu3d.inf"
    make_inf(inf_path)

    crt = SIGNING / "test-signing.crt"
    key = SIGNING / "test-signing.key"
    cer = SIGNING / "test-signing.cer"
    if not crt.is_file() or not key.is_file() or not cer.is_file():
        sys.exit(
            f"Missing signing key/certificate in {SIGNING}. "
            "Run ./scripts/gen_test_cert.sh first to generate a local test-signing certificate."
        )
    sign_time = (SIGNING / "SIGN_TIME").read_text().strip()

    all_files = sorted(p for p in DRV.rglob("*") if p.is_file())
    for p in all_files:
        if p.read_bytes()[:2] == b"MZ":
            sign_pe(p, crt, key, sign_time)
            print(f"Signed PE: {p.relative_to(DRV)}")

    # Build catalog hashes
    entries = []
    for p in all_files:
        res = subprocess.run([str(STRIP_PE), str(p)], capture_output=True)
        if res.returncode == 0 and len(res.stdout) > 0:
            digest = hashlib.sha1(res.stdout).hexdigest().upper()
            entries.append(f"{p.name}:{digest}:PE")
        else:
            digest = hashlib.sha1(p.read_bytes()).hexdigest().upper()
            entries.append(f"{p.name}:{digest}")

    entries.sort(key=lambda e: e.split(":")[1])
    hwids = "pci\\ven_1af4&dev_1050,pci\\ven_1af4&dev_1050&subsys_11001af4&rev_01"
    h = hashlib.sha256(("\n".join([hwids] + entries) + "\n").encode()).hexdigest()
    guid = f"{h[0:8]}-{h[8:12]}-4{h[13:16]}-8{h[17:20]}-{h[20:32]}"
    import datetime
    gen_time = datetime.datetime.fromtimestamp(int(sign_time), datetime.timezone.utc).strftime("%y%m%d%H%M%SZ")

    unsigned_cat = PKG / "viogpu3d.unsigned.cat"
    signed_cat = DRV / "viogpu3d.cat"
    cat_bytes = subprocess.check_output([
        str(CAT_BIN),
        "-G", guid,
        "-T", gen_time,
        "-O", "_v100_ARM64,_v100_ARM64_22H2,_v100_ARM64_24H2",
        "-A", "2:10.0",
        "-h", hwids,
        *entries,
    ])
    unsigned_cat.write_bytes(cat_bytes)
    subprocess.run(
        [
            "osslsigncode", "sign",
            "-certs", str(crt),
            "-key", str(key),
            "-h", "sha256",
            "-time", sign_time,
            "-in", str(unsigned_cat),
            "-out", str(signed_cat),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    unsigned_cat.unlink()

    for p in all_files + [signed_cat]:
        if p == signed_cat or p.read_bytes()[:2] == b"MZ":
            subprocess.run(["osslsigncode", "verify", "-CAfile", str(crt), "-in", str(p)], check=True, stdout=subprocess.DEVNULL)

    shutil.copy2(cer, PKG / "yttrium-test-signing.cer")
    for arch in ("arm64", "x86"):
        (PKG / "runtime" / arch).mkdir(parents=True, exist_ok=True)
        for fname in ("vulkan-1.dll", "vulkaninfo.exe"):
            dst = PKG / "runtime" / arch / fname
            shutil.copy2(VK_OUT / arch / fname, dst)
            sign_pe(dst, crt, key, sign_time)

    install_cmd = "\r\n".join([
        "@echo off",
        "net session >nul 2>&1 || (echo Run as Administrator! & pause & exit /b 1)",
        "cd /d \"%~dp0\"",
        "echo [1/5] Trusting test certificate...",
        "certutil -addstore -f Root yttrium-test-signing.cer",
        "certutil -addstore -f TrustedPublisher yttrium-test-signing.cer",
        "echo [2/5] Enabling test signing and disabling hibernation...",
        "bcdedit /set testsigning on",
        "powercfg /hibernate off",
        "echo [3/5] Installing Vulkan Loader (ARM64 + x86)...",
        "copy /y runtime\\arm64\\vulkan-1.dll %SystemRoot%\\System32\\vulkan-1.dll",
        "copy /y runtime\\x86\\vulkan-1.dll %SystemRoot%\\SysWOW64\\vulkan-1.dll",
        "echo [4/5] Installing Yttrium viogpu3d ARM64 driver...",
        "pnputil /add-driver driver\\viogpu3d.inf /install",
        "echo [5/5] Done. Reboot Windows to activate testsigning and viogpu3d.",
        "pause",
        "",
    ])
    (PKG / "Install-ARM64-3D.cmd").write_bytes(install_cmd.encode("ascii"))
    print(f"Package ready at {PKG}")


if __name__ == "__main__":
    main()
