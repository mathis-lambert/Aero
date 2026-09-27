#!/bin/zsh
# Runs the UI (E2E) tests into a unique result bundle and records how to reproduce the run.
# Usage: Scripts/run-e2e.sh [test-identifier …]   e.g. AeroUITests/BrowsingE2ETests
# Without identifiers it runs every E2E test except performance measurements (docs/PERFORMANCE.md).
set -euo pipefail

cd "${0:A:h}/.."
run_id="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)"
result="/tmp/aero-e2e-${run_id}.xcresult"
manifest="/tmp/aero-e2e-${run_id}.txt"
patch="/tmp/aero-e2e-${run_id}.patch"
# Preserve the tested working tree, including new fixtures and sources.
git diff --binary HEAD > "$patch"
while IFS= read -r -d '' file; do
    git diff --no-index --binary -- /dev/null "$file" >> "$patch" || [[ $? == 1 ]]
done < <(git ls-files --others --exclude-standard -z)
configuration="${AERO_E2E_CONFIGURATION:-Debug}"
derived_data="${AERO_E2E_DERIVED_DATA:-/tmp/aero-derived}"
command=(xcodebuild -project Aero.xcodeproj -scheme Aero -configuration "$configuration"
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived_data"
    -resultBundlePath "$result")
for test in "$@"; do command+=(-only-testing:"$test"); done
(( $# )) || command+=(-skip-testing:AeroUITests/LaunchPerformanceTests -skip-testing:AeroUITests/SpacesPerformanceTests)
command+=(test)

{
    print "command: ${(q)command[@]}"
    print "revision: $(git rev-parse HEAD)"
    print "working-tree patch: $patch"
    print "patch SHA-256: $(shasum -a 256 "$patch")"
    print "working tree:"; git status --short | sed 's/^/  /'
    print "xcode: $(xcodebuild -version | tr '\n' ' ')"
    print "macos: $(sw_vers -productVersion) ($(sw_vers -buildVersion)) $(uname -m)"
    print "fixtures: Tests/AeroUITests/Fixtures served by FixtureServer on localhost; AERO_TEST_DATA isolates app data"
} > "$manifest"

exit_code=0
"${command[@]}" || exit_code=$?
print "exit status: $exit_code" >> "$manifest"
print "Result bundle: $result\nManifest: $manifest"
exit $exit_code
