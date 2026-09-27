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

$dumpbinCommand = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
$dumpbinPath = if ($dumpbinCommand) { $dumpbinCommand.Source } else { $null }
if (-not $dumpbinPath) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $visualStudio = & $vswhere -latest -products * -property installationPath
        if ($visualStudio) {
            $toolchain = Join-Path $visualStudio "VC\Tools\MSVC"
            $dumpbinPath = (Get-ChildItem $toolchain -Filter dumpbin.exe -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "\\Hostx64\\x64\\dumpbin\.exe$" } |
                Sort-Object FullName -Descending |
                Select-Object -First 1).FullName
        }
    }
}
if (-not $dumpbinPath) { throw "dumpbin.exe is required to bundle FFmpeg runtime dependencies" }

$queue = [System.Collections.Generic.Queue[string]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in @("avformat", "avcodec", "swscale", "avutil")) {
    $library = Get-ChildItem $source -Filter "$name*.dll" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^$name(-\d+)?\.dll$" } |
        Sort-Object Name |
        Select-Object -First 1
    if (-not $library) { throw "FFmpeg DLL $name is missing from $source" }
    $queue.Enqueue($library.FullName)
}

while ($queue.Count -gt 0) {
    $libraryPath = $queue.Dequeue()
    $libraryName = [System.IO.Path]::GetFileName($libraryPath)
    if (-not $seen.Add($libraryName)) { continue }

    Copy-Item $libraryPath (Join-Path $bin $libraryName) -Force
    $dependencies = & $dumpbinPath /nologo /dependents $libraryPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect FFmpeg dependencies for $libraryName" }

    foreach ($match in [regex]::Matches(($dependencies -join "`n"), "(?im)^\s+([a-z0-9_.+-]+\.dll)\s*$")) {
        $dependency = $match.Groups[1].Value
        $dependencyPath = Join-Path $source $dependency
        if (Test-Path $dependencyPath) {
            $queue.Enqueue($dependencyPath)
        } elseif ($dependency -notmatch "^(api-ms-win-|ext-ms-win-)" -and -not (Test-Path (Join-Path $env:SystemRoot "System32\$dependency"))) {
            throw "FFmpeg dependency $dependency was not found in $source or Windows System32"
        }
    }
}

foreach ($name in @("avformat", "avcodec", "swscale", "avutil")) {
    if (-not (Get-ChildItem $bin -Filter "$name*.dll" -ErrorAction SilentlyContinue)) {
        throw "FFmpeg DLL $name is missing from the package"
    }
}
