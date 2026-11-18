@echo off
net session >nul 2>&1 || (echo Run as Administrator! & pause & exit /b 1)
cd /d "%~dp0"
echo [1/5] Trusting test certificate...
certutil -addstore -f Root yttrium-test-signing.cer
certutil -addstore -f TrustedPublisher yttrium-test-signing.cer
echo [2/5] Enabling test signing and disabling hibernation...
bcdedit /set testsigning on
powercfg /hibernate off
echo [3/5] Installing Vulkan Loader (ARM64 + x86)...
copy /y runtime\arm64\vulkan-1.dll %SystemRoot%\System32\vulkan-1.dll
copy /y runtime\x86\vulkan-1.dll %SystemRoot%\SysWOW64\vulkan-1.dll
echo [4/5] Installing Yttrium viogpu3d ARM64 driver...
pnputil /add-driver driver\viogpu3d.inf /install
echo [5/5] Done. Reboot Windows to activate testsigning and viogpu3d.
pause
