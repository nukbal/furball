#!/bin/sh
set -eu

app=$1
source_library=$2
molten_vk_prefix=$3
glslang_prefix=$4
spirv_tools_prefix=$5
ncnn_license=$6
binary="$app/Contents/MacOS/furball"
frameworks="$app/Contents/Frameworks"
destination="$frameworks/libncnn.1.dylib"
resources="$app/Contents/Resources"

if [ ! -f "$binary" ]; then
    echo "packaged furball executable is missing" >&2
    exit 1
fi
if [ ! -f "$source_library" ]; then
    echo "built ncnn Vulkan library is missing" >&2
    exit 1
fi

mkdir -p "$frameworks"
cp -L "$source_library" "$destination"
install_name_tool -id "@rpath/libncnn.1.dylib" "$destination"
install_name_tool -delete_rpath "$(dirname "$source_library")" "$binary" 2>/dev/null || true
mkdir -p "$resources"
{
    printf 'ncnn\n'
    cat "$ncnn_license"
    printf '\nMoltenVK\n'
    cat "$molten_vk_prefix/LICENSE"
    printf '\nglslang\n'
    cat "$glslang_prefix/LICENSE.txt"
    printf '\nSPIRV-Tools\n'
    cat "$spirv_tools_prefix/LICENSE"
} > "$resources/ThirdPartyNotices.txt"
if ! otool -l "$binary" | grep -F '@loader_path/../Frameworks' >/dev/null; then
    install_name_tool -add_rpath '@loader_path/../Frameworks' "$binary" 2>/dev/null || true
fi
