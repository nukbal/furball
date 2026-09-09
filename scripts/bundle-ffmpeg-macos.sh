#!/usr/bin/env bash
set -euo pipefail

app="$1"
ffmpeg_prefix="${2%/}"
binary="$app/Contents/MacOS/furball"
frameworks="$app/Contents/Frameworks"
ffmpeg_lib="$ffmpeg_prefix/lib"

test -x "$binary"
mkdir -p "$frameworks"

if command -v brew >/dev/null 2>&1; then
  brew_root="$(brew --prefix)"
else
  brew_root="$ffmpeg_prefix"
fi

queue=()
seen_basenames=""

resolve_dependency() {
  local dependency="$1"
  local basename candidate
  case "$dependency" in
    "$brew_root"/*|"$ffmpeg_prefix"/*)
      if [ -f "$dependency" ]; then
        printf '%s\n' "$dependency"
      fi
      ;;
    @rpath/*)
      basename="${dependency#@rpath/}"
      for candidate in "$ffmpeg_lib/$basename" "$brew_root/lib/$basename"; do
        if [ -f "$candidate" ]; then
          printf '%s\n' "$candidate"
          return
        fi
      done
      candidate="$(find "$brew_root" -name "$basename" \( -type f -o -type l \) -print -quit)"
      if [ -n "$candidate" ]; then
        printf '%s\n' "$candidate"
      fi
      ;;
  esac
}

add_source() {
  local source="$1"
  local basename="${source##*/}"
  case "|$seen_basenames|" in
    *"|$basename|"*) return ;;
  esac
  seen_basenames="$seen_basenames|$basename"
  queue+=("$source")
  rm -f "$frameworks/$basename"
  cp -L "$source" "$frameworks/$basename"
}

while read -r dependency _; do
  source="$(resolve_dependency "$dependency")"
  if [ -n "$source" ]; then
    add_source "$source"
  fi
done < <(otool -L "$binary" | tail -n +2)

index=0
while [ "$index" -lt "${#queue[@]}" ]; do
  source="${queue[$index]}"
  basename="${source##*/}"
  staged="$frameworks/$basename"
  install_name_tool -id "@rpath/$basename" "$staged" 2>/dev/null
  while read -r dependency _; do
    resolved="$(resolve_dependency "$dependency")"
    if [ -n "$resolved" ]; then
      dependency_basename="${resolved##*/}"
      add_source "$resolved"
      if [ "$dependency" != "@rpath/$dependency_basename" ]; then
        install_name_tool -change "$dependency" "@rpath/$dependency_basename" "$staged" 2>/dev/null
      fi
    fi
  done < <(otool -L "$source" | tail -n +2)
  index=$((index + 1))
done

while read -r dependency _; do
  resolved="$(resolve_dependency "$dependency")"
  if [ -n "$resolved" ]; then
    dependency_basename="${resolved##*/}"
    if [ "$dependency" != "@rpath/$dependency_basename" ]; then
      install_name_tool -change "$dependency" "@rpath/$dependency_basename" "$binary" 2>/dev/null
    fi
  fi
done < <(otool -L "$binary" | tail -n +2)

if ! otool -l "$binary" | grep -F '@loader_path/../Frameworks' >/dev/null; then
  install_name_tool -add_rpath '@loader_path/../Frameworks' "$binary" 2>/dev/null
fi

for name in libavformat libavcodec libswscale libavutil; do
  if ! find "$frameworks" -maxdepth 1 -name "$name*.dylib" -print -quit | grep -q .; then
    echo "FFmpeg dylib $name is missing from the app bundle" >&2
    exit 1
  fi
done

if otool -L "$binary" | grep -F "$brew_root/" >/dev/null; then
  echo "the app still references an absolute Homebrew dylib" >&2
  exit 1
fi
for library in "$frameworks"/*.dylib; do
  if otool -L "$library" | grep -F "$brew_root/" >/dev/null; then
    echo "$library still references an absolute Homebrew dylib" >&2
    exit 1
  fi
done

for library in "$frameworks"/*.dylib; do
  codesign --force --sign - --timestamp=none "$library" >/dev/null 2>&1
done
codesign --force --sign - --timestamp=none "$binary" >/dev/null 2>&1
codesign --force --sign - --timestamp=none "$app" >/dev/null 2>&1
codesign --verify --deep --strict "$app" >/dev/null 2>&1
