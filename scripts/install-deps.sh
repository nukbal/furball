#!/bin/sh

# install dav1d
brew install pkg-config dav1d

# install ffmpeg
curl -JL -o ./ffmpeg.7z https://evermeet.cx/ffmpeg/get
7z x ffmpeg.7z
mkdir src-tauri/bin
mv ffmpeg src-tauri/bin/ffmpeg-x86_64-apple-darwin

# Add Real-ESRGAN anime models
curl -OL https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip
7z x realesrgan-ncnn-vulkan-20220424-macos.zip
mv realesrgan-ncnn-vulkan src-tauri/bin/realesrgan-x86_64-apple-darwin
mkdir src-tauri/models
mv models/realesr-animevideov3-x2.bin src-tauri/models/realesr-animevideov3-x2.bin
mv models/realesr-animevideov3-x2.param src-tauri/models/realesr-animevideov3-x2.param
mv models/realesr-animevideov3-x4.bin src-tauri/models/realesr-animevideov3-x4.bin
mv models/realesr-animevideov3-x4.param src-tauri/models/realesr-animevideov3-x4.param
