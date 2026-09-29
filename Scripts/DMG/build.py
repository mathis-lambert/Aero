# /// script
# requires-python = ">=3.12"
# dependencies = ["dmgbuild==1.6.7"]
# ///
"""Build the Finder installation window without requiring a GUI session."""
from pathlib import Path
import sys

import dmgbuild

app, background, destination = map(Path, sys.argv[1:])
dmgbuild.build_dmg(str(destination), app.stem, settings={
    "format": "UDZO",
    "files": [str(app)],
    "symlinks": {"Applications": "/Applications"},
    "background": str(background),
    "window_rect": ((160, 160), (640, 360)),
    "default_view": "icon-view",
    "icon_size": 96,
    "text_size": 13,
    "icon_locations": {app.name: (176, 190), "Applications": (464, 190)},
})
