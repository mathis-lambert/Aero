#!/bin/zsh
# Xcode Cloud owns build-for-testing and test-without-building; never run UI tests in this hook.
set -euo pipefail
cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud must provide the repository path}"
Scripts/check-toolchain.sh
xcodebuild -downloadComponent MetalToolchain
