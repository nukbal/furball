#!/bin/sh
set -eu

ncnn_source=$1
molten_vk_prefix=$2
glslang_prefix=$3
output_archive=$4
build_dir="${output_archive}.build"
molten_vk_library="$molten_vk_prefix/lib/libMoltenVK.a"
molten_vk_headers="$molten_vk_prefix/libexec/include"

if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake is required; run scripts/install-deps.sh" >&2
    exit 1
fi
if [ ! -f "$molten_vk_library" ] || [ ! -f "$molten_vk_headers/vulkan/vulkan.h" ]; then
    echo "MoltenVK static library or Vulkan headers are missing; run scripts/install-deps.sh or set -Dmolten-vk-prefix" >&2
    exit 1
fi
if [ ! -f "$glslang_prefix/lib/cmake/glslang/glslangConfig.cmake" ] && [ ! -f "$glslang_prefix/lib/cmake/glslang/glslang-config.cmake" ]; then
    echo "glslang CMake package is missing; run scripts/install-deps.sh or set -Dglslang-prefix" >&2
    exit 1
fi

cmake -S "$(dirname "$0")/../libs/ncnn" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$glslang_prefix;$molten_vk_prefix" \
    -DNCNN_SOURCE_DIR="$ncnn_source" \
    -DMOLTENVK_PREFIX="$molten_vk_prefix" \
    -DVulkan_INCLUDE_DIR="$molten_vk_headers" \
    -DVulkan_LIBRARY="$molten_vk_library" \
    -DNCNN_VULKAN=ON \
    -DNCNN_SIMPLEVK=OFF \
    -DNCNN_SYSTEM_GLSLANG=ON \
    -DNCNN_SHARED_LIB=OFF \
    -DNCNN_DISABLE_RTTI=ON \
    -DNCNN_DISABLE_EXCEPTION=ON \
    -DNCNN_INT8=OFF \
    -DNCNN_BF16=OFF \
    -DNCNN_PIXEL_ROTATE=OFF \
    -DNCNN_PIXEL_AFFINE=OFF \
    -DNCNN_PIXEL_DRAWING=OFF \
    -DNCNN_OPENMP=OFF \
    -DNCNN_BUILD_TOOLS=OFF \
    -DNCNN_BUILD_EXAMPLES=OFF \
    -DNCNN_BUILD_BENCHMARK=OFF \
    -DNCNN_BUILD_TESTS=OFF

cmake --build "$build_dir" --target ncnn --config Release --parallel
mkdir -p "$(dirname "$output_archive")"
cp "$build_dir/ncnn/src/libncnn.a" "$output_archive"
