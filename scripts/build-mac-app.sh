#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="debug"
open_app="0"
for argument in "$@"; do
    case "$argument" in
        --release) configuration="release" ;;
        --open) open_app="1" ;;
        *) printf 'Usage: scripts/build-mac-app.sh [--release] [--open]\n' >&2; exit 2 ;;
    esac
done

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$repo_dir/.build/module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$repo_dir/.build/module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$repo_dir/.build/cache"
cd "$repo_dir"
# The native builder supports this dependency-free package with Command Line Tools as well as Xcode.
swift build --build-system native --cache-path "$repo_dir/.build/cache" --configuration "$configuration" --product MorningOperatorDesktop
binary_dir="$(swift build --build-system native --cache-path "$repo_dir/.build/cache" --configuration "$configuration" --show-bin-path)"
app_dir="$repo_dir/build/Morning Operator.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/MorningOperatorDesktop" "$app_dir/Contents/MacOS/MorningOperator"
cp "$repo_dir/Configuration/macOS-Info.plist" "$app_dir/Contents/Info.plist"
chmod +x "$app_dir/Contents/MacOS/MorningOperator"
codesign --force --sign - "$app_dir"
printf '\nBuilt %s\n' "$app_dir"
if [[ "$open_app" == "1" ]]; then open "$app_dir"; fi
