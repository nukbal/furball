@echo off

@REM install dav1d
choco install pkgconfiglite
vcpkg install dav1d:x64-windows

@REM set llvm clang for download
$VCINSTALLDIR = $(& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath)
powershell -Command "Add-Content $env:GITHUB_ENV 'LIBCLANG_PATH=${VCINSTALLDIR}\VC\Tools\LLVM\x64\bin`n\'"

@REM install ffmpeg
powershell -Command "Invoke-WebRequest 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.7z' -OutFile ffmpeg-release-full-shared.7z"
7z x ffmpeg-release-full-shared.7z
mkdir ffmpeg
mv ffmpeg-*/* ffmpeg/
mkdir src-tauri/bin
mv ffmpeg/bin/ffmpeg.exe src-tauri/bin/ffmpeg-x86_64-pc-windows-msvc.exe
powershell -Command "Add-Content $env:GITHUB_ENV 'FFMPEG_DIR=${pwd}\src-tauri\bin`n'"
powershell -Command "Add-Content $env:GITHUB_PATH '${pwd}\src-tauri\bin\bin`n'"

@REM Add Real-ESRGAN anime models

powershell -Command "Invoke-WebRequest 'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip' -OutFile realesrgan.zip"
7z x realesrgan.zip
mv realesrgan-ncnn-vulkan.exe src-tauri/bin/realesrgan-x86_64-pc-windows-msvc.exe
mv vcomp140.dll src-tauri/bin/vcomp140.dll
mv vcomp140d.dll src-tauri/bin/vcomp140d.dll
mkdir src-tauri/models
mv models/realesr-animevideov3-x2.bin src-tauri/models/realesr-animevideov3-x2.bin
mv models/realesr-animevideov3-x2.param src-tauri/models/realesr-animevideov3-x2.param
mv models/realesr-animevideov3-x4.bin src-tauri/models/realesr-animevideov3-x4.bin
mv models/realesr-animevideov3-x4.param src-tauri/models/realesr-animevideov3-x4.param
