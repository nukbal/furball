#!/usr/bin/env bash
set -euo pipefail

app="$1"
ffmpeg_prefix="${2%/}"
binary="$app/Contents/MacOS/furball"
frameworks="$app/Contents/Frameworks"
binary_dir="$(dirname "$binary")"

test -x "$binary"
test -d "$ffmpeg_prefix"
mkdir -p "$frameworks"

if command -v brew >/dev/null 2>&1; then
  brew_root="$(brew --prefix)"
else
  brew_root="$ffmpeg_prefix"
fi
ffmpeg_prefix="$(cd "$ffmpeg_prefix" && pwd -P)"
brew_root="$(cd "$brew_root" && pwd -P)"

queue=()
seen_basenames=""

is_system_dependency() {
  case "$1" in
    /System/*|/usr/lib/*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_dependency() {
  local dependency="$1"
  local image="$2"
  local basename candidate search_root
  case "$dependency" in
    /System/*|/usr/lib/*)
      ;;
    /*)
      if [ -f "$dependency" ]; then
        printf '%s\n' "$dependency"
      fi
      ;;
    @loader_path/*)
      candidate="$(dirname "$image")/${dependency#@loader_path/}"
      if [ -f "$candidate" ]; then
        printf '%s\n' "$candidate"
      fi
      ;;
    @executable_path/*)
      candidate="$binary_dir/${dependency#@executable_path/}"
      if [ -f "$candidate" ]; then
        printf '%s\n' "$candidate"
      fi
      ;;
    @rpath/*)
      basename="${dependency#@rpath/}"
      for candidate in "$frameworks/$basename" "$ffmpeg_prefix/lib/$basename" "$brew_root/lib/$basename"; do
        if [ -f "$candidate" ]; then
          printf '%s\n' "$candidate"
          return
        fi
      done
      for search_root in "$ffmpeg_prefix" "$brew_root"; do
        if [ ! -d "$search_root" ]; then
          continue
        fi
        candidate="$(find "$search_root" -name "$basename" \( -type f -o -type l \) -print -quit)"
        if [ -n "$candidate" ]; then
          printf '%s\n' "$candidate"
          return
        fi
      done
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
  if [ "$source" != "$frameworks/$basename" ]; then
    rm -f "$frameworks/$basename"
    cp -L "$source" "$frameworks/$basename"
  fi
}

while read -r dependency _; do
  if is_system_dependency "$dependency"; then
    continue
  fi
  source="$(resolve_dependency "$dependency" "$binary")"
  if [ -z "$source" ]; then
    echo "Could not resolve app dependency: $dependency" >&2
    exit 1
  fi
  add_source "$source"
done < <(otool -L "$binary" | tail -n +2)

index=0
while [ "$index" -lt "${#queue[@]}" ]; do
  source="${queue[$index]}"
  basename="${source##*/}"
  staged="$frameworks/$basename"
  install_name_tool -id "@rpath/$basename" "$staged" 2>/dev/null
  if ! otool -l "$staged" | grep -F '@loader_path' >/dev/null; then
    install_name_tool -add_rpath '@loader_path' "$staged" 2>/dev/null
  fi
  while read -r dependency _; do
    if is_system_dependency "$dependency"; then
      continue
    fi
    resolved="$(resolve_dependency "$dependency" "$source")"
    if [ -z "$resolved" ]; then
      echo "Could not resolve dependency of $source: $dependency" >&2
      exit 1
    fi
    dependency_basename="${resolved##*/}"
    add_source "$resolved"
    if [ "$dependency" != "@rpath/$dependency_basename" ]; then
      install_name_tool -change "$dependency" "@rpath/$dependency_basename" "$staged" 2>/dev/null
    fi
  done < <(otool -L "$source" | tail -n +2)
  index=$((index + 1))
done

while read -r dependency _; do
  if is_system_dependency "$dependency"; then
    continue
  fi
  resolved="$(resolve_dependency "$dependency" "$binary")"
  if [ -z "$resolved" ]; then
    echo "Could not resolve app dependency: $dependency" >&2
    exit 1
  fi
  dependency_basename="${resolved##*/}"
  if [ "$dependency" != "@rpath/$dependency_basename" ]; then
    install_name_tool -change "$dependency" "@rpath/$dependency_basename" "$binary" 2>/dev/null
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

verify_references() {
  local image="$1"
  local dependency basename
  while read -r dependency _; do
    if is_system_dependency "$dependency"; then
      continue
    fi
    case "$dependency" in
      @rpath/*)
        basename="${dependency#@rpath/}"
        if [ ! -f "$frameworks/$basename" ]; then
          echo "$image references a missing bundled library: $dependency" >&2
          exit 1
        fi
        ;;
      *)
        echo "$image still references an external library: $dependency" >&2
        exit 1
        ;;
    esac
  done < <(otool -L "$image" | tail -n +2)
}

verify_references "$binary"
for library in "$frameworks"/*.dylib; do
  verify_references "$library"
done

for library in "$frameworks"/*.dylib; do
  codesign --force --sign - --timestamp=none "$library" >/dev/null 2>&1
done
codesign --force --sign - --timestamp=none "$binary" >/dev/null 2>&1
codesign --force --sign - --timestamp=none "$app" >/dev/null 2>&1
codesign --verify --deep --strict "$app" >/dev/null 2>&1
