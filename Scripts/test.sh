#!/bin/zsh
# Runs one test plan into a unique result bundle and records how to reproduce the run. See docs/TESTING.md.
# Usage: Scripts/test.sh [unit|smoke|full|performance] [test-identifier …]
#   unit         package and app unit tests: seconds, after every change
#   smoke        unit tests and the core journeys: a few minutes, while developing (the default)
#   full         every test except performance: before a commit or a pull request
#   performance  launch, onboarding, rendering and many-spaces measurements, in Release
# Identifiers narrow the plan, for example: Scripts/test.sh full AeroUITests/SidebarJourneys
set -euo pipefail

cd "${0:A:h}/.."
plan="${1:-smoke}"
(( $# )) && shift
case "$plan" in
    unit) plan_name=Unit ;;
    smoke) plan_name=Smoke ;;
    full) plan_name=Full ;;
    performance) plan_name=Performance ;;
    *) print -u2 "Unknown plan: $plan (unit, smoke, full or performance)"; exit 1 ;;
esac
Scripts/check-toolchain.sh

run_id="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD)-$plan-$$"
result="/tmp/aero-tests-${run_id}.xcresult"
manifest="/tmp/aero-tests-${run_id}.txt"
patch="/tmp/aero-tests-${run_id}.patch"
# Preserve the tested working tree, including new fixtures and sources.
git diff --binary HEAD > "$patch"
while IFS= read -r -d '' file; do
    git diff --no-index --binary -- /dev/null "$file" >> "$patch" || [[ $? == 1 ]]
done < <(git ls-files --others --exclude-standard -z)

configuration=Debug
[[ "$plan" != performance ]] || configuration=Release
command=(xcodebuild ARCHS=arm64 -project Aero.xcodeproj -scheme 'Aero Dev' -testPlan "$plan_name" -configuration "$configuration"
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/build/DerivedData" -resultBundlePath "$result")
for test in "$@"; do command+=(-only-testing:"$test"); done
command+=(test)

{
    print "plan: $plan_name ($configuration)"
    print -r -- "command: ${(q)command[@]}"
    if [[ "$plan" != performance ]] && (( ! $# )); then
        print -r -- "package command: swift test --package-path Packages/BrowserKit"
    fi
    print "revision: $(git rev-parse HEAD)"
    print "working-tree patch: $patch"
    print "patch SHA-256: $(shasum -a 256 "$patch")"
    print "working tree:"; git status --short | sed 's/^/  /'
    print "xcode: $(xcodebuild -version | tr '\n' ' ')"
    print "macos: $(sw_vers -productVersion) ($(sw_vers -buildVersion)) $(uname -m)"
    print "fixtures: Tests/AeroUITests/Fixtures, pages served by FixtureServer on localhost; AERO_TEST_DATA isolates app data"
} > "$manifest"

exit_code=0
if [[ "$plan" != performance ]] && (( ! $# )); then
    swift test --package-path Packages/BrowserKit || exit_code=$?
fi
(( exit_code )) || "${command[@]}" || exit_code=$?
print "exit status: $exit_code" >> "$manifest"
print "Result bundle: $result\nManifest: $manifest"
exit $exit_code
