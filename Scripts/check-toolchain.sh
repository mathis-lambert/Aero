#!/bin/zsh
set -euo pipefail
source "${0:A:h}/../Configuration/Toolchain.env"
actual="$(xcodebuild -version)"
expected=$(printf 'Xcode %s\nBuild version %s' "$AERO_XCODE_VERSION" "$AERO_XCODE_BUILD")
if [[ "$actual" != "$expected" ]]; then
    print -u2 "Aero requires $expected. Selected: $actual. Set DEVELOPER_DIR to the matching Xcode."
    exit 1
fi
