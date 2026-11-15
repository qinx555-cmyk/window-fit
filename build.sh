#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1 && [[ -d /Library/Developer/CommandLineTools ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

mkdir -p build
build_dir="$PWD/build"
if [[ ${1:-} == --test ]]; then
    xcrun swiftc -warnings-as-errors Sources/WindowFitPolicy.swift Tests/WindowFitPolicyTests.swift -o "$build_dir/WindowFitTests"
    "$build_dir/WindowFitTests"
    exit
fi

stage="$(mktemp -d "$build_dir/.stage.XXXXXX")"
trap 'rm -r -- "$stage"' EXIT
app="$stage/窗口随屏.app"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
xcrun swiftc -warnings-as-errors -O -target "$(uname -m)-apple-macos13.0" \
    Sources/*.swift -o "$app/Contents/MacOS/WindowFit"
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$stage/窗口随屏.zip"

if [[ -d "$build_dir/窗口随屏.app" ]]; then
    rm -r -- "$build_dir/窗口随屏.app"
fi
mv "$app" "$build_dir/窗口随屏.app"
# Some synced folders attach Finder metadata when a bundle is moved into place.
xattr -d com.apple.FinderInfo "$build_dir/窗口随屏.app" 2>/dev/null || true
mv -f "$stage/窗口随屏.zip" "$build_dir/窗口随屏.zip"
printf '%s\n' "$build_dir/窗口随屏.app" "$build_dir/窗口随屏.zip"
