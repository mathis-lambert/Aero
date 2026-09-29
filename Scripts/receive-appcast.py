#!/usr/bin/env python3
"""Forced SSH command on the feed host. Requires Python 3.10+ (standard library only).

Install outside the writable feed directory. authorized_keys invokes this file with
that directory as its sole argument; SSH_ORIGINAL_COMMAND selects the channel.
The receiver preserves signed XML bytes. Signing is performed by trusted CI, not here.
"""
import fcntl
import os
from pathlib import Path
import re
import sys
import tempfile
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
MAX_BYTES = 2 * 1024 * 1024
TAG = {
    "stable": r"v\d+\.\d+\.\d+",
    "beta": r"v\d+\.\d+\.\d+-beta\.[1-9]\d*",
    "nightly": r"nightly-[0-9a-f]{40}",
}


def latest(data, channel):
    if channel not in TAG or len(data) > MAX_BYTES or b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
        raise ValueError("Invalid channel or feed size/DTD")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        raise ValueError("Invalid XML") from error
    if root.tag != "rss":
        raise ValueError("Expected RSS appcast")
    versions = []
    for item in root.findall("./channel/item"):
        version = item.findtext(SPARKLE + "version", "")
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version):
            raise ValueError("Expected numeric build version")
        enclosure = item.find("enclosure")
        if enclosure is None or not enclosure.get(SPARKLE + "edSignature"):
            raise ValueError("Missing signed archive")
        url = enclosure.get("url", "")
        match = re.fullmatch(r"https://github\.com/mathis-lambert/Aero/releases/download/(" + TAG[channel] + r")/Aero-\1-arm64\.zip", url)
        if not match or not re.fullmatch(r"[1-9][0-9]*", enclosure.get("length", "")):
            raise ValueError("Unexpected archive URL or size")
        parts = tuple(map(int, version.split(".")))
        versions.append((parts + (0,) * (3 - len(parts)), url, enclosure.get(SPARKLE + "edSignature"), enclosure.get("length")))
    if not versions:
        raise ValueError("Empty appcast")
    return max(versions)


def publish(directory, channel, data):
    incoming = latest(data, channel)
    target = directory / (channel + ".xml")
    # The lock covers comparison and replacement, including concurrent SSH connections.
    with (directory / ("." + channel + ".lock")).open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if target.exists():
            current = latest(target.read_bytes(), channel)
            if incoming[0] < current[0]:
                raise ValueError("Refusing an older build")
            if incoming[0] == current[0] and incoming != current:
                raise ValueError("Refusing different artifacts for an existing build")
        descriptor, name = tempfile.mkstemp(prefix="." + channel + "-", suffix=".tmp", dir=directory)
        try:
            with os.fdopen(descriptor, "wb") as output:
                os.fchmod(output.fileno(), 0o644)
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
            os.replace(name, target)
            folder = os.open(directory, os.O_RDONLY)
            try:
                os.fsync(folder)
            finally:
                os.close(folder)
        finally:
            Path(name).unlink(missing_ok=True)
    print("Published", channel, "build", ".".join(map(str, incoming[0])))


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: receive-appcast.py <existing-updates-directory>")
        channel = os.environ.get("SSH_ORIGINAL_COMMAND", "")
        publish(Path(sys.argv[1]), channel, sys.stdin.buffer.read(MAX_BYTES + 1))
    except (ValueError, OSError) as error:
        sys.exit(str(error))
