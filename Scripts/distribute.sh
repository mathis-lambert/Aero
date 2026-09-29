#!/bin/zsh
# Prepare official artifacts; publishing is owned by GitHub Actions.
set -euo pipefail
cd "${0:A:h}/.."
source Scripts/build-support.sh
[[ "${1:-}" != --help ]] || { print 'Usage: Scripts/distribute.sh <tag-at-HEAD>'; exit 0; }
[[ $# == 1 ]] || fail 'Usage: Scripts/distribute.sh <tag-at-HEAD>'
tag="$1"
[[ -z "$(git status --porcelain)" ]] || fail 'Distribution requires a clean checkout.'
[[ "$(git rev-parse --verify "refs/tags/$tag^{commit}")" == "$(git rev-parse HEAD)" ]] || fail 'Tag must point to HEAD.'
if [[ "$tag" =~ '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-beta\.([1-9][0-9]*)$' ]]; then
    channel=beta; configuration=Beta; product='Aero Beta'
elif [[ "$tag" =~ '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ]]; then
    channel=stable; configuration=Stable; product=Aero
elif [[ "$tag" =~ '^nightly-[0-9a-f]{40}$' ]]; then
    [[ "${tag#nightly-}" == "$(git rev-parse HEAD)" ]] || fail 'Nightly tag must identify HEAD.'
    channel=nightly; configuration=Nightly; product='Aero Nightly'
else
    fail 'Expected vX.Y.Z, vX.Y.Z-beta.N or nightly-<full-commit-SHA>.'
fi
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
[[ "$APPLE_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || fail 'Invalid Apple Team ID.'
: "${APPLE_API_KEY_ID:?Set APPLE_API_KEY_ID}"
: "${APPLE_API_ISSUER_ID:?Set APPLE_API_ISSUER_ID}"
: "${APPLE_API_KEY_PATH:?Set APPLE_API_KEY_PATH to the local .p8 file}"
[[ -f "$APPLE_API_KEY_PATH" ]] || fail 'Notarization key file not found.'
signing=developer-id
prepare_build
if [[ "$channel" != nightly ]]; then
    [[ "${${tag#v}%%-beta.*}" == "$version" ]] || fail 'Tag version must match Configuration/Version.xcconfig.'
fi
[[ "$(git rev-parse --is-shallow-repository)" == false ]] || fail 'Distribution requires full Git history.'
# Releasing another beta of the same commit must still advance CFBundleVersion.
build_number="$(git rev-list --count HEAD).0"
[[ "$channel" != beta ]] || build_number="$(git rev-list --count HEAD).${tag##*-beta.}"
: "${SPARKLE_PUBLIC_ED_KEY:?Set SPARKLE_PUBLIC_ED_KEY}"
: "${SPARKLE_PRIVATE_KEY_FILE:?Set SPARKLE_PRIVATE_KEY_FILE}"
[[ -s "$SPARKLE_PRIVATE_KEY_FILE" ]] || fail 'Sparkle private key file not found.'
[[ "$SPARKLE_PUBLIC_ED_KEY" =~ '^[A-Za-z0-9+/]{43}=$' ]] || fail 'Invalid Sparkle public key encoding.'
[[ "$(printf '%s' "$SPARKLE_PUBLIC_ED_KEY" | base64 --decode | wc -c | tr -d ' ')" == 32 ]] || fail 'Invalid Sparkle public key.'
sparkle_tools="$output/sparkle-tools"
Scripts/sparkle-tools.sh "$sparkle_tools"
archive="$output/$product.xcarchive"
command=(xcodebuild ARCHS=arm64 -project Aero.xcodeproj -scheme "$product" -configuration "$configuration"
    -onlyUsePackageVersionsFromResolvedFile
    -destination 'generic/platform=macOS' -derivedDataPath "$PWD/build/DistributionDerivedData"
    -archivePath "$archive" "CURRENT_PROJECT_VERSION=$build_number" "AERO_REVISION=$revision"
    AERO_UPDATES_ENABLED=YES "SPARKLE_PUBLIC_ED_KEY=$SPARKLE_PUBLIC_ED_KEY"
    "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" 'CODE_SIGN_IDENTITY=Developer ID Application' archive)
write_manifest
"${command[@]}" 2>&1 | tee "$output/archive.log"
cat > "$output/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Developer ID Application</string>
<key>teamID</key><string>$APPLE_TEAM_ID</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$output/ExportOptions.plist" \
    -exportPath "$output/export" 2>&1 | tee "$output/export.log"
app="$output/export/$product.app"
notarize() {
    local artifact="$1" label="$2" staple_target="$3" submission result submit_exit=0
    result="$output/notary-$label.json"
    xcrun notarytool submit "$artifact" --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER_ID" --wait --timeout 30m --output-format json > "$result" || submit_exit=$?
    submission=$(plutil -extract id raw "$result" 2>/dev/null) || fail "No submission ID; see $result"
    # A rejected submission may exit nonzero. Retrieve its diagnostics before failing.
    if ! xcrun notarytool log "$submission" --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER_ID" "$output/notary-$label-log.json"; then
        print -u2 "Notary log unavailable; submission $submission may still be processing."
    fi
    (( submit_exit == 0 )) || fail "Notarization failed or timed out; see $result"
    [[ "$(plutil -extract status raw "$result")" == Accepted ]] || fail "Notarization rejected; see $output/notary-$label-log.json"
    xcrun stapler staple "$staple_target"
    xcrun stapler validate "$staple_target"
}
codesign --verify --deep --strict "$app"
codesign -d --entitlements :- "$app" > "$output/entitlements.plist" 2>/dev/null
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$output/entitlements.plist" 2>/dev/null || true)" == true ]]; then
    fail 'Distribution must not allow debugging (get-task-allow).'
fi
[[ "$(lipo -archs "$app/Contents/MacOS/$product")" == arm64 ]] || fail 'Distribution must be arm64 only.'
ditto -c -k --keepParent "$app" "$output/notary-app.zip"
notarize "$output/notary-app.zip" app "$app"
syspolicy_check distribution "$app"
dmg="$output/Aero-$tag-arm64.dmg"
create_dmg "$app" "$dmg"
codesign --sign 'Developer ID Application' --timestamp "$dmg"
notarize "$dmg" dmg "$dmg"
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
symbols="$archive/dSYMs/$product.app.dSYM"
[[ -s "$symbols/Contents/Resources/DWARF/$product" ]] || fail "Missing app dSYM in $archive"
binary_uuid=$(xcrun dwarfdump --uuid "$app/Contents/MacOS/$product" | awk '{print $2}')
symbols_uuid=$(xcrun dwarfdump --uuid "$symbols" | awk '{print $2}')
[[ -n "$binary_uuid" && "$binary_uuid" == "$symbols_uuid" ]] || fail 'App dSYM does not match the released binary.'
app_zip="$output/Aero-$tag-arm64.zip"
symbols_zip="$output/Aero-$tag-arm64-dSYMs.zip"
ditto -c -k --keepParent "$app" "$app_zip"
ditto -c -k --keepParent "$archive/dSYMs" "$symbols_zip"
mkdir "$output/public"
cp "$dmg" "$output/manifest.txt" "$output/public/"
mv "$app_zip" "$symbols_zip" "$output/public/"
(cd "$output/public"; shasum -a 256 "${dmg:t}" "${app_zip:t}" "${symbols_zip:t}" > SHA256SUMS)
# Generate a signed feed from only the app ZIP; dSYMs and DMGs are not updater inputs.
feed_directory="$output/appcast"
mkdir "$feed_directory"
cp "$output/public/${app_zip:t}" "$feed_directory/"
# Only 404 means a first release. A network/server failure must not silently discard history.
feed_status=$(curl --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 60 --max-filesize 2097152 --output "$feed_directory/$channel.xml" \
    --write-out '%{http_code}' "https://getaero.app/updates/$channel.xml")
case "$feed_status" in
    200) "$sparkle_tools/bin/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" --verify "$feed_directory/$channel.xml" ;;
    404) rm "$feed_directory/$channel.xml" ;;
    *) fail "Could not retrieve existing appcast (HTTP $feed_status)." ;;
esac
# Embed plain release notes so clients need no extra endpoint or unsigned remote HTML.
if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
    cp "$RELEASE_NOTES_FILE" "$output/release-notes.md"
else
    git log -1 --format=%s > "$output/release-notes.md"
fi
cp "$output/release-notes.md" "$feed_directory/${app_zip:t:r}.md"
"$sparkle_tools/bin/generate_appcast" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    --download-url-prefix "https://github.com/mathis-lambert/Aero/releases/download/$tag/" \
    --maximum-deltas 0 --maximum-versions 5 --embed-release-notes --link https://getaero.app \
    -o "$feed_directory/$channel.xml" "$feed_directory"
"$sparkle_tools/bin/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" --verify "$feed_directory/$channel.xml"
# generate_appcast can warn about a key mismatch without failing. Require a signed
# entry for this exact build before exposing any release assets.
python3 - "$feed_directory/$channel.xml" "$channel" "$build_number" <<'PYTHON'
from pathlib import Path
import runpy
import sys
receiver = runpy.run_path("Scripts/receive-appcast.py")
latest = receiver["latest"](Path(sys.argv[1]).read_bytes(), sys.argv[2])
expected = tuple(map(int, sys.argv[3].split(".")))
if latest[0] != expected + (0,) * (3 - len(expected)):
    raise SystemExit("Generated appcast does not announce this build")
PYTHON
cp "$feed_directory/$channel.xml" "$output/public/"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    print "output=$output" >> "$GITHUB_OUTPUT"
    print "channel=$channel" >> "$GITHUB_OUTPUT"
fi
print "Ready to publish: $output/public"
