#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${1:-release}
app_dir="$project_dir/dist/CopyDock.app"
build_dir="$project_dir/.build/$configuration"
cache_dir="${COPYDOCK_CACHE_DIR:-/private/tmp/copydock-swiftpm-cache}"

cd "$project_dir"
swift build \
    --disable-sandbox \
    --configuration "$configuration" \
    --product CopyDock \
    --cache-path "$cache_dir" \
    -debug-info-format none \
    --enable-experimental-strip-products

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/CopyDock" "$app_dir/Contents/MacOS/CopyDock"
cp "$project_dir/Support/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Assets/CopyDockIcon.png" "$app_dir/Contents/Resources/CopyDockIcon.png"
chmod +x "$app_dir/Contents/MacOS/CopyDock"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
