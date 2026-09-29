#!/bin/bash
# Publish the appcast already attached to an immutable GitHub Release. Safe to retry.
set -euo pipefail
cd "$(dirname "$0")/.."
tag="${1:?Usage: Scripts/publish-update.sh <release-tag>}"
case "$tag" in
    nightly-*) channel=nightly ;;
    v*-beta.*) channel=beta ;;
    v*) channel=stable ;;
    *) echo 'Invalid release tag.' >&2; exit 1 ;;
esac
: "${UPDATE_HOST:?Set UPDATE_HOST}"
: "${UPDATE_USER:?Set UPDATE_USER}"
: "${UPDATE_SSH_KEY:?Set UPDATE_SSH_KEY}"
: "${UPDATE_KNOWN_HOSTS:?Set UPDATE_KNOWN_HOSTS}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
umask 077
printf '%s\n' "$UPDATE_SSH_KEY" > "$work/key"
printf '%s\n' "$UPDATE_KNOWN_HOSTS" > "$work/known_hosts"
gh release download "$tag" --repo mathis-lambert/Aero --pattern "$channel.xml" --dir "$work"
# Verify all archive links resolve before advertising this release. No GitHub token reaches clients.
python3 - "$work/$channel.xml" <<'PY'
import sys
import urllib.request
import xml.etree.ElementTree as ET
for item in ET.parse(sys.argv[1]).findall('./channel/item/enclosure'):
    url = item.attrib['url']
    if not url.startswith('https://github.com/mathis-lambert/Aero/releases/download/'):
        raise SystemExit('Unexpected archive URL')
    with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=30) as response:
        if response.status != 200:
            raise SystemExit('Archive unavailable')
PY
ssh -i "$work/key" -p "${UPDATE_PORT:-22}" -o BatchMode=yes -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -o "UserKnownHostsFile=$work/known_hosts" \
    "$UPDATE_USER@$UPDATE_HOST" "$channel" < "$work/$channel.xml"
curl --fail --silent --show-error --retry 3 --connect-timeout 15 --max-time 60 --max-filesize 2097152 "https://getaero.app/updates/$channel.xml" -o "$work/live.xml"
cmp "$work/$channel.xml" "$work/live.xml"
