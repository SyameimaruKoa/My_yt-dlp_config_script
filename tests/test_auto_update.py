import contextlib
import importlib.util
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

source = Path(__file__).resolve().parents[1] / "tools" / "yt_dlp_auto_update.py"
spec = importlib.util.spec_from_file_location("yt_dlp_auto_update", source)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class StartupUpdateTests(unittest.TestCase):
    def test_skip_update(self):
        with mock.patch.dict(os.environ, {"YT_DLP_SKIP_UPDATE": "1"}), mock.patch.object(updater.subprocess, "run") as run:
            self.assertEqual(updater.update(), 0)
            run.assert_not_called()

    def test_pip_update_and_extras(self):
        result = mock.Mock(returncode=0, stdout="")
        with tempfile.TemporaryDirectory() as temp:
            with mock.patch.dict(os.environ, {"YT_DLP_SKIP_UPDATE": "0"}), mock.patch.object(updater.sys, "prefix", temp):
                with mock.patch.object(updater.subprocess, "run", return_value=result) as run, mock.patch.object(updater, "package_version", side_effect=["old", "new"]):
                    with contextlib.redirect_stderr(io.StringIO()) as output:
                        self.assertEqual(updater.update(), 0)
                    self.assertIn("old -> new", output.getvalue())
                    command = run.call_args.args[0]
                    self.assertIn("--pre", command)
                    self.assertIn("--upgrade", command)
                    self.assertTrue(any(value.startswith("yt-dlp[default,curl-cffi") for value in command))

    def test_failed_update_keeps_installed_version(self):
        result = mock.Mock(returncode=1, stdout="network unavailable")
        with tempfile.TemporaryDirectory() as temp:
            with mock.patch.dict(os.environ, {"YT_DLP_SKIP_UPDATE": "0"}, clear=False):
                with mock.patch.object(updater.sys, "prefix", temp), mock.patch.object(updater.subprocess, "run", return_value=result):
                    with mock.patch.object(updater, "package_version", return_value="installed"):
                        with contextlib.redirect_stderr(io.StringIO()) as output:
                            self.assertEqual(updater.update(), 0)
                        self.assertIn("インストール済み", output.getvalue())


if __name__ == "__main__":
    unittest.main()
