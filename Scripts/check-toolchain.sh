#!/bin/zsh
set -euo pipefail
source "${0:A:h}/../Configuration/Toolchain.env"
actual="$(xcodebuild -version)"
for build in ${=AERO_XCODE_BUILDS}; do
    [[ "$actual" == "$(printf 'Xcode %s\nBuild version %s' "$AERO_XCODE_VERSION" "$build")" ]] && exit 0
done
print -u2 "Aero requires Xcode $AERO_XCODE_VERSION (build ${AERO_XCODE_BUILDS// / or }). Selected: $actual. Set DEVELOPER_DIR to the matching Xcode."
exit 1
