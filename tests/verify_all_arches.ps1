param(
    [string]$RootDir = "C:\Yttrium-ARM64-3D"
)

$out = "$RootDir\verify_all_arches.txt"
$tools = "$RootDir\tools"
$rt = "$RootDir\runtime"

$items = @(
  @("GL_D3D_ARM64", "$tools\gl_d3d_probe_arm64.exe", ""),
  @("GL_D3D_X86",   "$tools\gl_d3d_probe_x86.exe", ""),
  @("GL_D3D_X64",   "$tools\gl_d3d_probe_x64.exe", ""),
  @("VULKAN_ARM64", "$rt\arm64\vulkaninfo.exe", "--summary"),
  @("VULKAN_X86",   "$rt\x86\vulkaninfo.exe", "--summary"),
  @("VULKAN_X64",   "$tools\vulkaninfo_x64.exe", "--summary")
)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("=== Tool paths exist ===")
foreach ($it in $items) {
  [void]$sb.AppendLine("$($it[0]): $($it[1]) -> $(Test-Path $it[1])")
}
foreach ($it in $items) {
  $label = $it[0]; $exe = $it[1]; $arg = $it[2]
  [void]$sb.AppendLine("`n=== $label ===")
  if (!(Test-Path $exe)) { [void]$sb.AppendLine("MISSING: $exe"); continue }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.Arguments = $arg
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  [void]$sb.AppendLine("EXIT=$($p.ExitCode)")
  if ($stdout) { [void]$sb.AppendLine($stdout.TrimEnd()) }
  if ($stderr) { [void]$sb.AppendLine("STDERR:`n$($stderr.TrimEnd())") }
}
$sb.ToString() | Out-File -Encoding UTF8 $out
"VERIFY_DONE" | Out-File -Encoding UTF8 "$RootDir\verify_all_done.txt"
