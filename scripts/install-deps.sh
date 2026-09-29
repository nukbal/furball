#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
models="$project_root/src/models"
python_venv="$project_root/.venv-coreml"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

brew install zig ffmpeg python@3.12
mkdir -p "$models"
rm -rf \
  "$models/RealESRGAN_animevideo_522_fp16.mlpackage" \
  "$models/RealESRGAN_x2plus_522_fp16.mlpackage" \
  "$models/RealESRGAN_x4plus_522_fp16.mlpackage" \
  "$models/RealESRGAN_anime_6B_522_fp16.mlpackage" \
  "$models/RealESRGAN_general_522_fp16.mlpackage"
rm -f \
  "$models/realesr-animevideov3-x2.bin" \
  "$models/realesr-animevideov3-x2.param" \
  "$models/realesr-animevideov3-x4.bin" \
  "$models/realesr-animevideov3-x4.param"

python="$(brew --prefix python@3.12)/bin/python3.12"
if [[ ! -x "$python_venv/bin/python" ]]; then
  "$python" -m venv "$python_venv"
fi
"$python_venv/bin/python" -m pip install -r "$project_root/scripts/requirements-coreml.txt"

realesrgan_revision="v0.2.3.0"
for scale in 2 4; do
  realesrgan_package="$models/RealESRGAN_animevideo_x${scale}_522_fp16.mlpackage"
  if [[ ! -f "$realesrgan_package/Manifest.json" || ! -f "$realesrgan_package/Data/com.apple.CoreML/model.mlmodel" || ! -f "$realesrgan_package/Data/com.apple.CoreML/weights/weight.bin" ]]; then
    realesrgan_weights="$work/RealESRGANv2-animevideo-xsx${scale}.pth"
    curl --fail --location --retry 3 \
      --output "$realesrgan_weights" \
      "https://github.com/xinntao/Real-ESRGAN/releases/download/$realesrgan_revision/RealESRGANv2-animevideo-xsx${scale}.pth"
    "$python_venv/bin/python" "$project_root/scripts/convert-realesrgan-to-coreml.py" \
      --weights "$realesrgan_weights" \
      --scale "$scale" \
      --output "$realesrgan_package"
  fi
done

pipersr_package="$models/PiperSR_2x_256.mlpackage"
pipersr_revision="8daecfccbbe023de6580e7eecbff3d44a51d0b13"
pipersr_base="https://huggingface.co/ModelPiper/PiperSR-2x/resolve/$pipersr_revision/PiperSR_2x_256.mlpackage"
if [[ ! -f "$pipersr_package/Manifest.json" || ! -f "$pipersr_package/Data/com.apple.CoreML/model.mlmodel" || ! -f "$pipersr_package/Data/com.apple.CoreML/weights/weight.bin" ]]; then
  mkdir -p "$pipersr_package/Data/com.apple.CoreML/weights"
  curl --fail --location --retry 3 --output "$pipersr_package/Manifest.json" "$pipersr_base/Manifest.json"
  curl --fail --location --retry 3 --output "$pipersr_package/Data/com.apple.CoreML/model.mlmodel" "$pipersr_base/Data/com.apple.CoreML/model.mlmodel"
  curl --fail --location --retry 3 --output "$pipersr_package/Data/com.apple.CoreML/weights/weight.bin" "$pipersr_base/Data/com.apple.CoreML/weights/weight.bin"
fi

if [[ ! -f "$models/LICENSE-PiperSR" ]]; then
  curl --fail --location --retry 3 \
    --output "$models/LICENSE-PiperSR" \
    https://raw.githubusercontent.com/ModelPiper/PiperSR/f164924de22e52a91177b05897bc6cc9b05a0c07/MODEL_LICENSE
fi

if [[ ! -f "$models/LICENSE-Real-ESRGAN" ]]; then
  curl --fail --location --retry 3 \
    --output "$models/LICENSE-Real-ESRGAN" \
    https://raw.githubusercontent.com/xinntao/Real-ESRGAN/v0.2.3.0/LICENSE
fi
