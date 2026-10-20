#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root/app"
fvm flutter pub get
fvm dart run build_runner build
fvm dart run slang
fvm flutter build apk --split-per-abi
# Release signing uses this fork's app/android/key.properties.