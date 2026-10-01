#!/bin/zsh
# Refreshes the filter lists bundled with the app, the ones ad blocking uses until its first update.
# EasyList and EasyPrivacy are © The EasyList authors, dual-licensed GPLv3 / CC BY-SA 3.0.
# A download replaces its list only once complete and headed as an Adblock Plus list.
# Usage: Scripts/update-filter-lists.sh
set -euo pipefail

cd "${0:A:h}/.."
for list in easylist easyprivacy; do
    target="App/Resources/FilterLists/$list.txt"
    download="$(mktemp "$target.XXXXXX")"
    trap 'rm -f "$download"' EXIT
    curl --fail --silent --show-error --location --max-time 60 --max-filesize 33554432 \
        --output "$download" "https://easylist.to/easylist/$list.txt"
    if [[ "$(head -c 13 "$download")" != "[Adblock Plus" ]]; then
        print -u2 "$list: the download is not an Adblock Plus list"
        exit 1
    fi
    mv -f "$download" "$target"
    trap - EXIT
    print "$list: $(wc -l < "$target" | tr -d ' ') lines"
done
