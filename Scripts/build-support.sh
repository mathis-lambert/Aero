# Shared by build.sh and distribute.sh. The caller sets strict zsh options and repo cwd.
fail() { print -u2 -- "$*"; exit 1; }

prepare_build() {
    Scripts/check-toolchain.sh
    revision=$(git rev-parse HEAD)
    version=$(sed -n 's/^MARKETING_VERSION = //p' Configuration/Version.xcconfig)
    [[ "$version" =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ]] || fail 'Invalid MARKETING_VERSION'
    mkdir -p build/artifacts
    output=$(mktemp -d "$PWD/build/artifacts/$(date -u +%Y%m%dT%H%M%SZ)-${revision[1,8]}-XXXXXX")
    print "Artifacts: $output"
}

write_manifest() {
    {
        print "channel: $channel"
        print "configuration: $configuration"
        print "version: $version"
        print "revision: $revision"
        print "tag: ${tag:-none}"
        print "signing: ${signing:-ad-hoc}"
        print "xcode: $(xcodebuild -version | tr '\n' ' ')"
        print "sdk: $(xcrun --show-sdk-version)"
        print "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
        print "architecture: arm64"
        print "command: ${(q)command[@]}"
        print "working tree:"
        git status --short
    } > "$output/manifest.txt"
    # Local builds can include uncommitted source; retain it for reproduction.
    git diff --binary HEAD > "$output/source.patch"
    while IFS= read -r -d '' file; do
        git diff --no-index --binary -- /dev/null "$file" >> "$output/source.patch" || [[ $? == 1 ]]
    done < <(git ls-files --others --exclude-standard -z)
}

create_dmg() {
    local source_app="$1" destination="$2" background="$output/dmg-background.tiff"
    (( $+commands[uv] )) || fail 'DMG packaging requires uv (https://docs.astral.sh/uv/).'
    swift -swift-version 6 Scripts/DMG/render.swift "$background"
    uv run --locked Scripts/DMG/build.py "$source_app" "$background" "$destination"
    hdiutil verify "$destination"
}
