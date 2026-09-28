#!/bin/zsh
# Refreshes the Public Suffix List bundled with the app, which decides which saved passwords a site
# is offered (docs/PASSWORDS.md › Matching sites). © Mozilla Foundation contributors, MPL 2.0.
# Usage: Scripts/update-public-suffix-list.sh
set -euo pipefail

cd "${0:A:h}/.."
destination=App/Resources/PublicSuffixList/public_suffix_list.dat
temporary=$(mktemp App/Resources/PublicSuffixList/.public-suffix.XXXXXX)
trap 'rm -f "$temporary"' EXIT
curl --fail --silent --show-error --location --max-time 60 \
    --output "$temporary" https://publicsuffix.org/list/public_suffix_list.dat
grep -q '^// ===BEGIN ICANN DOMAINS===' "$temporary"
grep -q '^// ===BEGIN PRIVATE DOMAINS===' "$temporary"
chmod 644 "$temporary"
mv "$temporary" "$destination"
print "public_suffix_list: $(grep -cv '^\(//\|$\)' "$destination" | tr -d ' ') rules"
