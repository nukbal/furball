#!/usr/bin/env bash
set -euo pipefail

binary="$1"
package_root="$2"
ffmpeg_prefix="${3%/}"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$package_root/furball.app"
contents="$app/Contents"
version="$(sed -n 's/^[[:space:]]*\.version = "\([^"]*\)".*/\1/p' "$project_root/build.zig.zon")"

if [[ -z "$version" ]]; then
  echo "Could not read the package version from build.zig.zon" >&2
  exit 1
fi

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$binary" "$contents/MacOS/furball"
cp "$project_root/assets/icon.icns" "$contents/Resources/icon.icns"

cat > "$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Furball</string>
    <key>CFBundleExecutable</key>
    <string>furball</string>
    <key>CFBundleIconFile</key>
    <string>icon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>dev.nukbal.furball</string>
    <key>CFBundleName</key>
    <string>Furball</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

printf 'APPL????' > "$contents/PkgInfo"
bash "$project_root/scripts/bundle-ffmpeg-macos.sh" "$app" "$ffmpeg_prefix"
