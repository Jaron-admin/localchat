#!/usr/bin/env bash
set -euo pipefail

# Requires Flutter's Linux build dependencies and appimage-builder.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root/app"
fvm flutter pub get
fvm dart run build_runner build
fvm dart run slang
fvm flutter build linux

stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/localchat-appimage.XXXXXX")"
mkdir -p "$stage_dir/AppDir"
cp -a build/linux/x64/release/bundle/. "$stage_dir/AppDir/"
for size in 32 128 256; do
  icon_dir="$stage_dir/AppDir/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$icon_dir"
  cp "assets/img/logo-${size}.png" "$icon_dir/localchat.png"
done
cd "$stage_dir"
appimage-builder --recipe "$repo_root/support/build/appimage/AppImageBuilder_x86_64.yml"
mkdir -p "$repo_root/app/dist"
cp LocalChat-*-x86_64.AppImage "$repo_root/app/dist/"
printf 'AppImage created in %s/app/dist; staging retained at %s\n' "$repo_root" "$stage_dir"