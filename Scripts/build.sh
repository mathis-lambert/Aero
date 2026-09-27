#!/bin/zsh
# Build Aero Dev from any checkout, without an Apple account.
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-support.sh
usage() { print 'Usage: Scripts/build.sh [build|run|dmg] [--configuration Debug|Release]'; }
action=build
if (( $# )) && [[ "$1" != --* ]]; then
    action="$1"; shift
fi
[[ "$action" == build || "$action" == run || "$action" == dmg ]] || { usage; exit 1; }
configuration=Debug
[[ "$action" != dmg ]] || configuration=Release
while (( $# )); do
    case "$1" in
        --help) usage; exit 0 ;;
        --configuration)
            (( $# >= 2 )) || { usage; exit 1; }
            configuration="$2"; shift 2
            ;;
        *) usage; exit 1 ;;
    esac
done
[[ "$configuration" == Debug || "$configuration" == Release ]] || fail 'Local builds use Debug or Release.'
channel=dev
prepare_build
command=(xcodebuild ARCHS=arm64 -project Aero.xcodeproj -scheme 'Aero Dev' -configuration "$configuration"
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$PWD/build/DerivedData"
    "AERO_REVISION=$revision" build)
write_manifest
"${command[@]}" 2>&1 | tee "$output/build.log"
app="$PWD/build/DerivedData/Build/Products/$configuration/Aero Dev.app"
codesign --verify --deep --strict "$app"
case "$action" in
    run) open "$app" ;;
    dmg)
        dmg="$output/Aero-Dev-$version-${revision[1,8]}-local-arm64.dmg"
        create_dmg "$app" "$dmg"
        (cd "$output"; shasum -a 256 "${dmg:t}" > SHA256SUMS)
        print "DMG: $dmg"
        ;;
esac
print "App: $app"
