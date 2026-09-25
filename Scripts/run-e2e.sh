#!/bin/zsh
# Runs the UI (E2E) tests into a unique result bundle and records how to reproduce the run.
# Usage: Scripts/run-e2e.sh [-only-testing identifier …]   e.g. AuroUITests/BrowsingE2ETests
set -euo pipefail

cd "${0:A:h}/.."
run_id="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
result="/tmp/auro-e2e-${run_id}.xcresult"
manifest="/tmp/auro-e2e-${run_id}.txt"
command=(xcodebuild -project Auro.xcodeproj -scheme Auro -configuration Debug
    -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/auro-derived
    -resultBundlePath "$result")
for test in "$@"; do command+=(-only-testing:"$test"); done
command+=(test)

{
    print "command: ${(q)command[@]}"
    print "revision: $(git rev-parse HEAD)"
    print "working tree:"; git status --short | sed 's/^/  /'
    print "xcode: $(xcodebuild -version | tr '\n' ' ')"
    print "macos: $(sw_vers -productVersion) ($(sw_vers -buildVersion)) $(uname -m)"
    print "fixtures: Tests/AuroUITests/Fixtures served by FixtureServer on localhost; AURO_TEST_DATA isolates app data"
} > "$manifest"

exit_code=0
"${command[@]}" || exit_code=$?
print "exit status: $exit_code" >> "$manifest"
print "Result bundle: $result\nManifest: $manifest"
exit $exit_code
