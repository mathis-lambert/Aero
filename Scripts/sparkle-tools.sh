#!/bin/bash
# Fetch the exact tools matching the application's pinned Sparkle dependency.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(python3 - <<'PYTHON'
import json
from pathlib import Path
lock = Path("Aero.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
print(next(pin["state"]["version"] for pin in json.loads(lock.read_text())["pins"] if pin["identity"] == "sparkle"))
PYTHON
)
[[ "$version" == 2.10.0 ]] || { echo 'Update the Sparkle tools checksum when upgrading the framework.' >&2; exit 1; }
destination="${1:?Usage: Scripts/sparkle-tools.sh <directory>}"
mkdir -p "$destination"
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 300 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$destination/Sparkle.tar.xz"
printf '%s  %s\n' 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c' "$destination/Sparkle.tar.xz" | shasum -a 256 --check
tar -xf "$destination/Sparkle.tar.xz" -C "$destination"
