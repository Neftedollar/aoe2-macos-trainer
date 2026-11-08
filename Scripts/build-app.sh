#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_path="$PWD/.build/AoE2MacTrainer.app"

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/AoE2MacTrainer" "$app_path/Contents/MacOS/AoE2MacTrainer"
cp "App/Info.plist" "$app_path/Contents/Info.plist"

for bundle in "$binary_dir"/*.bundle; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" "$app_path/Contents/Resources/"
    fi
done

codesign --force --deep --sign - "$app_path"
echo "Built $app_path"
