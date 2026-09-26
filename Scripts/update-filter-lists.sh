#!/bin/zsh
# Refreshes the filter lists bundled with the app, the ones ad blocking uses until its first update.
# EasyList and EasyPrivacy are © The EasyList authors, dual-licensed GPLv3 / CC BY-SA 3.0.
# Usage: Scripts/update-filter-lists.sh
set -euo pipefail

cd "${0:A:h}/.."
for list in easylist easyprivacy; do
    curl --fail --silent --show-error --location --max-time 60 \
        --output "App/Resources/FilterLists/$list.txt" "https://easylist.to/easylist/$list.txt"
    print "$list: $(wc -l < App/Resources/FilterLists/$list.txt | tr -d ' ') lines"
done
