#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_path="$PWD/.build/AoE2MacTrainer.app"
bundle_name="AoE2MacTrainer_AoE2MacTrainer.bundle"
resource_source="$PWD/Sources/AoE2MacTrainer/Resources"
resource_output="$binary_dir/$bundle_name"
if [ -d "$resource_output/Contents/Resources" ]; then
    resource_output="$resource_output/Contents/Resources"
fi

# Fail before touching the previous app if SwiftPM omitted or retained old resources.
for resource in builds.json trainer_template.xs food_observation_template.xs ThirdPartyNotices.txt; do
    if ! cmp -s "$resource_source/$resource" "$resource_output/$resource"; then
        echo "Missing or stale SwiftPM resource: $bundle_name/$resource" >&2
        exit 1
    fi
done

stage_dir="$(mktemp -d "$PWD/.build/app-staging.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
staged_app="$stage_dir/AoE2MacTrainer.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/AoE2MacTrainer" "$staged_app/Contents/MacOS/AoE2MacTrainer"
cp "App/Info.plist" "$staged_app/Contents/Info.plist"
cp -R "$binary_dir/$bundle_name" "$staged_app/Contents/Resources/"

codesign --force --deep --sign - "$staged_app"
# Replace the whole app so deleted resources cannot survive a previous build.
rm -rf "$app_path"
mv "$staged_app" "$app_path"
echo "Built $app_path"
