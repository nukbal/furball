param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][string]$FfmpegPrefix
)

$bin = Join-Path $PackagePath "bin"
$executable = Join-Path $bin "furball.exe"
$source = Join-Path $FfmpegPrefix "bin"

if (-not (Test-Path $executable)) { throw "packaged furball.exe is missing" }
if (-not (Test-Path $source)) { throw "FFmpeg bin directory is missing: $source" }
New-Item -ItemType Directory -Force -Path $bin | Out-Null
Copy-Item (Join-Path $source "*.dll") $bin -Force

foreach ($name in @("avformat", "avcodec", "swscale", "avutil")) {
    if (-not (Get-ChildItem $bin -Filter "$name*.dll" -ErrorAction SilentlyContinue)) {
        throw "FFmpeg DLL $name is missing from the package"
    }
}
