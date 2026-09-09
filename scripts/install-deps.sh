#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
brew install zig ffmpeg


# Add Real-ESRGAN anime models
curl -OL https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip
7z x realesrgan-ncnn-vulkan-20220424-macos.zip
mkdir src/models
mv models/realesr-animevideov3-x2.bin src/models/realesr-animevideov3-x2.bin
mv models/realesr-animevideov3-x2.param src/models/realesr-animevideov3-x2.param
mv models/realesr-animevideov3-x4.bin src/models/realesr-animevideov3-x4.bin
mv models/realesr-animevideov3-x4.param src/models/realesr-animevideov3-x4.param
