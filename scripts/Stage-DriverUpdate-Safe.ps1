# Safe update script for Windows 11 ARM64 running under QEMU 10.0.13 (virtio-gpu-gl-pci blob=on).
# Avoids calling `pnputil /add-driver ... /install` while the GPU is live (prevents QEMU blob[4] abort).
# Run in an elevated (Administrator) PowerShell inside the guest, then perform `shutdown /s /t 0` and cold-boot via `bvm boot-3d`.
param(
    [string]$PackageDir = "C:\Yttrium-ARM64-3D"
)

$ErrorActionPreference = 'Stop'

Write-Host "=== [1/5] Ensuring test certificate trust and testsigning ==="
certutil -addstore -f Root "$PackageDir\yttrium-test-signing.cer" | Out-Null
certutil -addstore -f TrustedPublisher "$PackageDir\yttrium-test-signing.cer" | Out-Null
bcdedit /set testsigning on | Out-Null

Write-Host "=== [2/5] Updating Vulkan Loader (System32 ARM64X + SysWOW64 x86) ==="
Copy-Item -Force "$PackageDir\runtime\arm64\vulkan-1.dll" "C:\Windows\System32\vulkan-1.dll"
Copy-Item -Force "$PackageDir\runtime\x86\vulkan-1.dll" "C:\Windows\SysWOW64\vulkan-1.dll"

Write-Host "=== [3/5] Staging INF into DriverStore WITHOUT live device restart ==="
pnputil.exe /add-driver "$PackageDir\driver\viogpu3d.inf"

$targetSysHash = (Get-FileHash "$PackageDir\driver\viogpu3d.sys" -Algorithm SHA256).Hash
$matchedDir = $null
foreach ($d in (Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Directory -Filter "viogpu3d.inf_arm64_*" | Sort-Object LastWriteTime -Descending)) {
    $sysFile = Join-Path $d.FullName "viogpu3d.sys"
    if (Test-Path $sysFile) {
        $h = (Get-FileHash $sysFile -Algorithm SHA256).Hash
        if ($h -eq $targetSysHash -and -not $matchedDir) {
            $matchedDir = $d.FullName
        }
    }
}
if (-not $matchedDir) {
    throw "Failed to locate staged viogpu3d.sys ($targetSysHash) in DriverStore!"
}
Write-Host "Matched DriverStore folder: $matchedDir"

$relRepo = $matchedDir -replace '^C:\\Windows\\', '\SystemRoot\'
[Microsoft.Win32.Registry]::SetValue('HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\viogpu3d', 'ImagePath', "$relRepo\viogpu3d.sys", [Microsoft.Win32.RegistryValueKind]::ExpandString)
[Microsoft.Win32.Registry]::SetValue('HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\vgpusrv', 'ImagePath', "$matchedDir\vgpusrv.exe", [Microsoft.Win32.RegistryValueKind]::ExpandString)

Write-Host "=== [4/5] Applying TDR timeouts (15s) and system-managed pagefile ==="
$gdKey = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
[Microsoft.Win32.Registry]::SetValue($gdKey, 'TdrDelay', 15, [Microsoft.Win32.RegistryValueKind]::DWord)
[Microsoft.Win32.Registry]::SetValue($gdKey, 'TdrDdiDelay', 15, [Microsoft.Win32.RegistryValueKind]::DWord)
[Microsoft.Win32.Registry]::SetValue('HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management', 'PagingFiles', @('C:\pagefile.sys 0 0'), [Microsoft.Win32.RegistryValueKind]::MultiString)

if (Test-Path 'C:\ProgramData\Yttrium\yttrium.ini') {
    Remove-Item 'C:\ProgramData\Yttrium\yttrium.ini' -Force
}

Write-Host "=== [5/5] Staged cleanly. Now run: shutdown /s /t 0  and boot cold with: bvm boot-3d ==="
