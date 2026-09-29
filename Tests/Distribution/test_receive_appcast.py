"""Failure modes: malformed feeds, cross-channel archives, out-of-order publication,
conflicting same-build artifacts, interrupted writes and exposure of partial XML.
The receiver is tested in isolation because an app journey cannot exercise SSH publication.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("receiver", Path(__file__).parents[2] / "Scripts/receive-appcast.py")
receiver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receiver)


def feed(build="12.0", tag="v0.1.0", extra=""):
    return f'''<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><item><sparkle:version>{build}</sparkle:version><enclosure url="https://github.com/mathis-lambert/Aero/releases/download/{tag}/Aero-{tag}-arm64.zip" sparkle:edSignature="signature" length="1" type="application/octet-stream"/>{extra}</item></channel></rss>'''.encode()


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
            receiver.publish(Path(folder), "beta", feed("12.1", "v0.1.0-beta.1"))
            receiver.publish(Path(folder), "nightly", feed("12.0", "nightly-" + "a" * 40))


if __name__ == "__main__":
    unittest.main()
