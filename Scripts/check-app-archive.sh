#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
repo_root="$PWD"
archive_path="${1:-$repo_root/AoE2MacTrainer-macos.zip}"
case "$archive_path" in /*) ;; *) archive_path="$PWD/$archive_path" ;; esac
scratch="$(mktemp -d "${TMPDIR:-/tmp}/aoe2-app-check.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Bound execution and distinguish an expected diagnostic from a crash or kill.
check_resources() {
    python3 - "$1" "$2" <<'PYTHON'
import subprocess
import sys
binary, expected = sys.argv[1], int(sys.argv[2])
try:
    result = subprocess.run([binary, "--check-resources"], capture_output=True, text=True, timeout=30)
except subprocess.TimeoutExpired:
    sys.exit("Resource check exceeded 30 seconds")
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
marker = "Resource check OK" if expected == 0 else "Resource check failed:"
output = result.stdout if expected == 0 else result.stderr
if result.returncode != expected or marker not in output:
    sys.exit(f"Unexpected resource-check result: exit={result.returncode}, expected={expected}, marker={marker!r}")
PYTHON
}

ditto -x -k "$archive_path" "$scratch/extracted"
app="$scratch/extracted/AoE2MacTrainer.app"
binary="$app/Contents/MacOS/AoE2MacTrainer"
bundle_relative="Contents/Resources/AoE2MacTrainer_AoE2MacTrainer.bundle"
if [ -d "$app/$bundle_relative/Contents/Resources" ]; then
    bundle_relative="$bundle_relative/Contents/Resources"
fi
test -x "$binary"
test -s "$app/$bundle_relative/ThirdPartyNotices.txt"
codesign --verify --deep --strict "$app"

# Keep the build tree present: negative copies must fail even when a fallback
# bundle is available there. Run from outside the checkout to test relocation.
cd "$scratch"
check_resources "$binary" 0

# Exercise errors on disposable copies; never alter the archive being shipped.
no_bundle="$scratch/missing-bundle.app"
ditto "$app" "$no_bundle"
mv "$no_bundle/Contents/Resources/AoE2MacTrainer_AoE2MacTrainer.bundle" "$scratch/removed.bundle"
check_resources "$no_bundle/Contents/MacOS/AoE2MacTrainer" 1
for resource in builds.json trainer_template.xs food_observation_template.xs; do
    damaged="$scratch/missing-$resource.app"
    ditto "$app" "$damaged"
    rm "$damaged/$bundle_relative/$resource"
    check_resources "$damaged/Contents/MacOS/AoE2MacTrainer" 1
done
corrupt="$scratch/corrupt.app"
ditto "$app" "$corrupt"
printf '%s\n' '{invalid json' > "$corrupt/$bundle_relative/builds.json"
check_resources "$corrupt/Contents/MacOS/AoE2MacTrainer" 1

echo "Archived application resource checks passed"
