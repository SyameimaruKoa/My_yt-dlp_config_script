import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.install_ffmpeg import install_ffmpeg


class InstallFfmpegTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ffmpeg = self.root / "source-ffmpeg.exe"
        self.ffprobe = self.root / "source-ffprobe.exe"
        self.ffmpeg.write_bytes(b"ffmpeg-test")
        self.ffprobe.write_bytes(b"ffprobe-test")
        self.destination = self.root / "output path 日本語"
        self.calls = []

    def resolve(self):
        return str(self.ffmpeg), str(self.ffprobe)

    def verify(self, args, check, stdout):
        self.assertEqual(args[1], "-version")
        self.assertTrue(check)
        self.assertEqual(stdout, subprocess.DEVNULL)
        self.assertTrue(Path(args[0]).exists())
        self.calls.append(args)

    def test_installs_both_executables_into_unicode_path(self):
        result = install_ffmpeg(self.destination, self.resolve, self.verify)
        self.assertEqual(result, [self.destination / "ffmpeg.exe", self.destination / "ffprobe.exe"])
        self.assertEqual(result[0].read_bytes(), b"ffmpeg-test")
        self.assertEqual(result[1].read_bytes(), b"ffprobe-test")
        self.assertEqual(len(self.calls), 2)

    def test_fallback_to_copy_if_hardlink_is_unavailable(self):
        with patch("tools.install_ffmpeg.os.link", side_effect=OSError("cross-device")):
            install_ffmpeg(self.destination, self.resolve, self.verify)
        self.assertEqual((self.destination / "ffmpeg.exe").read_bytes(), b"ffmpeg-test")
        self.assertEqual((self.destination / "ffprobe.exe").read_bytes(), b"ffprobe-test")

    def test_failed_verification_preserves_existing_executables(self):
        self.destination.mkdir()
        (self.destination / "ffmpeg.exe").write_bytes(b"old-ffmpeg")
        (self.destination / "ffprobe.exe").write_bytes(b"old-ffprobe")
        def fail_verify(args, check, stdout):
            raise subprocess.CalledProcessError(1, args)
        with self.assertRaises(subprocess.CalledProcessError):
            install_ffmpeg(self.destination, self.resolve, fail_verify)
        self.assertEqual((self.destination / "ffmpeg.exe").read_bytes(), b"old-ffmpeg")
        self.assertEqual((self.destination / "ffprobe.exe").read_bytes(), b"old-ffprobe")
        self.assertEqual(sorted(p.name for p in self.destination.iterdir()), ["ffmpeg.exe", "ffprobe.exe"])

    def test_helper_has_help(self):
        script = Path(__file__).resolve().parents[1] / "tools" / "install_ffmpeg.py"
        result = subprocess.run([sys.executable, str(script), "--help"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Usage:", result.stdout)


if __name__ == "__main__":
    unittest.main()
