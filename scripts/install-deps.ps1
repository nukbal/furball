$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
choco install zig -y
if ($LASTEXITCODE -ne 0) { throw "Failed to install Zig" }

$vcpkgRoot = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { 'C:\vcpkg' }
& (Join-Path $vcpkgRoot 'vcpkg.exe') install ffmpeg:x64-windows
if ($LASTEXITCODE -ne 0) { throw "Failed to install FFmpeg development libraries" }
