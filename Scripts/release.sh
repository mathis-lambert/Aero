#!/bin/zsh
# Builds the Release app signed with Developer ID, has Apple notarize it, and staples the ticket.
# Usage: Scripts/release.sh
# Once per Mac, store the notary credentials in the keychain under the profile this script uses:
#   xcrun notarytool store-credentials aero-notary --apple-id <Apple ID> --team-id 69548S4JY3
# (it asks for an app-specific password, made at account.apple.com). AERO_NOTARY_PROFILE names another profile.
set -euo pipefail

cd "${0:A:h}/.."
team=69548S4JY3
profile="${AERO_NOTARY_PROFILE:-aero-notary}"
output=/tmp/aero-release
archive="$output/Aero.xcarchive"
app="$output/Aero.app"
upload="$output/Aero.zip"

xcrun notarytool history --keychain-profile "$profile" > /dev/null 2>&1 || {
    print -u2 "No notary credentials under \"$profile\". Store them once with:"
    print -u2 "  xcrun notarytool store-credentials $profile --apple-id <Apple ID> --team-id $team"
    exit 1
}

rm -rf "$output"
mkdir -p "$output"
cat > "$output/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>teamID</key><string>$team</string>
</dict>
</plist>
PLIST

# Exporting signs again with a secure timestamp, which notarization requires.
xcodebuild -project Aero.xcodeproj -scheme Aero -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath /tmp/aero-release-derived -archivePath "$archive" archive
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$output/ExportOptions.plist" -exportPath "$output"

ditto -c -k --keepParent "$app" "$upload"
xcrun notarytool submit "$upload" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose=2 "$app"
print "Notarized: $app"
