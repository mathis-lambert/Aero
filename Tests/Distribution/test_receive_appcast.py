"""Failure modes: malformed feeds, archives in the wrong feed or Sparkle channel (a beta outside the beta channel would
reach everyone), out-of-order publication within a channel, conflicting same-build artifacts, interrupted writes and
exposure of partial XML.
The receiver is tested in isolation because an app journey cannot exercise SSH publication.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("receiver", Path(__file__).parents[2] / "Scripts/receive-appcast.py")
receiver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receiver)


def item(build="12.0", tag="v0.1.0", channel=None):
    marker = f"<sparkle:channel>{channel}</sparkle:channel>" if channel else ""
    return f'''<item><sparkle:version>{build}</sparkle:version>{marker}<enclosure url="https://github.com/mathis-lambert/Aero/releases/download/{tag}/Aero-{tag}-arm64.zip" sparkle:edSignature="signature" length="1" type="application/octet-stream"/></item>'''


def feed(build="12.0", tag="v0.1.0", items=None):
    return ('<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>'
            + (items if items is not None else item(build, tag)) + "</channel></rss>").encode()


class PublicationTests(unittest.TestCase):
    def test_first_repeat_older_and_conflict(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            receiver.publish(root, "stable", feed())
            self.assertEqual((root / "stable.xml").read_bytes(), feed())
            receiver.publish(root, "stable", feed())
            with self.assertRaises(ValueError):
                receiver.publish(root, "stable", feed("11.0"))
            with self.assertRaises(ValueError):
                receiver.publish(root, "stable", feed(tag="v0.1.1"))
            self.assertEqual((root / "stable.xml").read_bytes(), feed())
            receiver.publish(root, "stable", feed("13.0", "v0.1.1"))
            self.assertEqual((root / "stable.xml").stat().st_mode & 0o777, 0o644)
            self.assertFalse(list(root.glob("*.tmp")))

    def test_invalid_inputs_preserve_previous(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            receiver.publish(root, "stable", feed())
            for bad in [b"not xml", b"<!DOCTYPE rss><rss/>", feed("NaN"), feed(tag="v0.1.0-beta.1"),
                        feed().replace(b"https://github.com/", b"https://elsewhere.test/"),
                        feed().replace(b'edSignature="signature"', b'edSignature=""')]:
                with self.assertRaises(ValueError):
                    receiver.publish(root, "stable", bad)
            self.assertEqual((root / "stable.xml").read_bytes(), feed())
            with self.assertRaises(ValueError):
                receiver.publish(root, "../stable", feed())

    def test_channels(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            beta = item("12.2", "v0.1.0-beta.2", "beta")
            receiver.publish(root, "stable", feed(items=beta))
            # The stable release of the beta's commit is an older build than the beta, in another channel.
            receiver.publish(root, "stable", feed(items=item() + beta))
            receiver.publish(root, "stable", feed(items=item("13.0", "v0.1.1") + beta))
            with self.assertRaises(ValueError, msg="dropping the beta channel"):
                receiver.publish(root, "stable", feed("14.0", "v0.1.2"))
            with self.assertRaises(ValueError, msg="an older beta"):
                receiver.publish(root, "stable", feed(items=item("13.0", "v0.1.1") + item("12.1", "v0.1.0-beta.1", "beta")))
            receiver.publish(root, "nightly", feed("12.0", "nightly-" + "a" * 40))
            for name, bad in [("nightly", feed("14.0", "v0.1.0")), ("stable", feed("14.0", "nightly-" + "a" * 40)),
                              ("stable", feed(items=item("14.0", "v0.2.0-beta.1") + beta)),
                              ("stable", feed(items=item("14.0", "v0.2.0", "beta") + beta)),
                              ("nightly", feed(items=item("14.0", "nightly-" + "b" * 40, "beta"))), ("beta", feed())]:
                with self.assertRaises(ValueError, msg=f"{name} refuses {bad[-200:]}"):
                    receiver.publish(root, name, bad)


if __name__ == "__main__":
    unittest.main()
