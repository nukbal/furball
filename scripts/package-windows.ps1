param(
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$FfmpegPrefix
)

$ErrorActionPreference = "Stop"
$packagePath = Join-Path $PackageRoot "windows"
$bin = Join-Path $packagePath "bin"

Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $packagePath
New-Item -ItemType Directory -Force -Path $bin | Out-Null
Copy-Item $ExecutablePath (Join-Path $bin "furball.exe") -Force
& (Join-Path $PSScriptRoot "bundle-ffmpeg-windows.ps1") $packagePath $FfmpegPrefix
