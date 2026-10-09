#!/bin/bash
set -euo pipefail

printf 'Morning Operator development environment\n'
printf 'macOS: '
sw_vers -productVersion
printf 'Developer directory: '
xcode-select -p
printf 'Swift: '
swift --version
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen --version
else
    printf 'XcodeGen is missing. Install it before generating the iOS project.\n'
fi

if ! xcodebuild -version 2>/dev/null; then
    printf '\nFull Xcode is not selected. Command Line Tools can build the Mac package, but cannot build/run iOS UI tests.\n'
    printf 'Install/open full Xcode, install its iOS platform, then select that Xcode in Settings > Locations.\n'
    exit 2
fi

printf '\niOS SDKs:\n'
xcodebuild -showsdks
printf '\nPaired/available devices (choose a specific identifier; no device is selected automatically):\n'
xcrun devicectl list devices
printf '\nPhone Developer Mode, Trust, unlock, team signing and Apple model readiness require checks on the actual phone.\n'
