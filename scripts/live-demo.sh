#!/bin/bash
# Owner-present live morning demo on the tethered iPhone (docs/DEVICE-SETUP.md).
# Usage: scripts/live-demo.sh [--device ID] [--team TEAM] [--reels N] [--any]
#
# The demo reads Messages and Mail aloud and may type a spoken draft. XCTest's own
# activity log records typed text, so this script keeps the result bundle and test
# logs in a private temporary directory, prints only test status lines, and deletes
# everything on exit, including Ctrl-C.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
device="00008130-001E318020FA8D3A"
team="U6Z87CS4W3"
reels="10"
any="0"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device) device="$2"; shift 2 ;;
        --team) team="$2"; shift 2 ;;
        --reels) reels="$2"; shift 2 ;;
        --any) any="1"; shift ;;
        --help|-h) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

for marker in CI GITHUB_ACTIONS CONTINUOUS_INTEGRATION; do
    value="${!marker:-}"
    if [[ -n "$value" && "$value" != "false" && "$value" != "0" ]]; then
        echo "The live morning demo never runs in CI ($marker is set)." >&2
        exit 1
    fi
done

work="$(mktemp -d "${TMPDIR:-/tmp}/mo-live-demo.XXXXXX")"
derived="$repo_dir/.build/iphone"
cleanup() {
    rm -rf "${work:?}"
    rm -rf "${derived:?}/Logs/Test"
}
trap cleanup EXIT INT TERM

cd "$repo_dir"
set +e
# Only lines that start with a status marker are printed: a draft containing the
# words "Test Case" mid-line cannot pass the anchored filter.
TEST_RUNNER_MO_LIVE_DEMO=1 \
TEST_RUNNER_MO_LIVE_DEMO_REELS="$reels" \
TEST_RUNNER_MO_LIVE_DEMO_ANY="$any" \
TEST_RUNNER_CI="${CI:-}" \
TEST_RUNNER_GITHUB_ACTIONS="${GITHUB_ACTIONS:-}" \
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild test \
    -project MorningOperator.xcodeproj -scheme MorningLiveDemo \
    -destination "id=$device" \
    -derivedDataPath "$derived" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$team" \
    -only-testing:MorningOperatorUITests/LiveMorningDemoTests \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 1800 \
    -resultBundlePath "$work/Results.xcresult" \
    2>&1 | grep -E --line-buffered '^(Test Case |Test Suite |\*\* TEST |xcodebuild: error)'
status="${PIPESTATUS[0]}"
exit "$status"
