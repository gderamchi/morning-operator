#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v xcodegen >/dev/null 2>&1 || { printf 'XcodeGen is required.\n' >&2; exit 2; }
for required in Package.swift project.yml Configuration/iOS-Info.plist; do
    [[ -f "$repo_dir/$required" ]] || { printf 'Missing project input: %s\n' "$required" >&2; exit 2; }
done
[[ -d "$repo_dir/Sources/MorningOperator" ]] || { printf 'App sources are missing.\n' >&2; exit 2; }
[[ -d "$repo_dir/UITests" ]] || { printf 'UI tests are missing.\n' >&2; exit 2; }
xcodegen generate --spec "$repo_dir/project.yml" --project "$repo_dir"
printf 'Generated %s/MorningOperator.xcodeproj. Generation does not compile or sign the app.\n' "$repo_dir"
