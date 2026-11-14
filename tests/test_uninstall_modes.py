import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(os.name == "posix", "Linux shell test")
class UninstallModesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = pathlib.Path(self.temp.name)
        self.root = base / "checkout"
        self.root.mkdir()
        self.home = base / "home"
        self.home.mkdir()
        self.data = base / "data"
        source = pathlib.Path(__file__).resolve().parents[1]
        shutil.copy2(source / "uninstall_yt-dlp.sh", self.root / "uninstall_yt-dlp.sh")
        (self.root / "setup_yt-dlp.sh").write_text("#!/bin/bash\n")
        migration = self.root / "tools" / "migration"
        migration.mkdir(parents=True)
        shutil.copy2(source / "tools" / "migration" / "remove-standalone.sh",
                     migration / "remove-standalone.sh")
        runtime = self.root / ".runtime" / "linux"
        python = runtime / "venv" / "bin" / "python"
        python.parent.mkdir(parents=True)
        python.write_text("#!/bin/sh\nexit 0\n")
        python.chmod(0o755)
        self.wrapper = runtime / "bin" / "yt-dlp"
        self.wrapper.parent.mkdir(parents=True)
        self.wrapper.write_text("#!/bin/sh\n# yt-dlp venv wrapper\n")
        self.wrapper.chmod(0o755)
        bin_dir = self.home / ".local" / "bin"
        bin_dir.mkdir(parents=True)
        (bin_dir / "yt-dlp").symlink_to(self.wrapper)
        config = self.root / "yt-dlp config"
        config.write_text("--version\n")
        config_dir = self.home / ".config" / "yt-dlp"
        config_dir.mkdir(parents=True)
        (config_dir / "config").symlink_to(config)
        old_venv = self.data / "yt-dlp" / "venv"
        old_venv.mkdir(parents=True)
        (old_venv / "pyvenv.cfg").write_text("home = old\n")
        bin_python = old_venv / "bin" / "python"
        bin_python.parent.mkdir()
        bin_python.write_text("#!/bin/sh\nexit 0\n")
        bin_python.chmod(0o755)
        self.old_venv = old_venv
        self.runtime = runtime
        self.env = dict(os.environ, HOME=str(self.home), XDG_DATA_HOME=str(self.data))

    def call(self, *args):
        return subprocess.run(["bash", str(self.root / "uninstall_yt-dlp.sh"), *args],
                              env=self.env, cwd=self.home, check=True,
                              capture_output=True, text=True)

    def test_cleanup_only_preserves_current_runtime(self):
        output = self.call("--cleanup-only").stdout
        self.assertIn("現行", output)
        self.assertTrue(self.runtime.exists())
        self.assertTrue((self.home / ".local" / "bin" / "yt-dlp").is_symlink())
        self.assertTrue((self.home / ".config" / "yt-dlp" / "config").is_symlink())
        self.assertFalse(self.old_venv.exists())
        self.assertTrue(self.root.exists())

    def test_full_dry_run_does_not_delete(self):
        self.call("--dry-run", "--keep-repository")
        self.assertTrue(self.runtime.exists())
        self.assertTrue(self.old_venv.exists())

    def test_full_removes_current_and_legacy_when_repo_retained(self):
        self.call("--keep-repository")
        self.assertFalse(self.runtime.exists())
        self.assertFalse(self.old_venv.exists())
        self.assertFalse((self.home / ".local" / "bin" / "yt-dlp").exists())
        self.assertTrue(self.root.exists())

    @unittest.skipUnless(shutil.which("git"), "Git is required")
    def test_default_full_uninstall_removes_modified_checkout(self):
        remote = pathlib.Path(self.temp.name) / "origin.git"
        subprocess.run(["git", "init", "--bare", "-b", "main", str(remote)], check=True,
                       capture_output=True)
        subprocess.run(["git", "-C", str(self.root), "init", "-b", "main"], check=True,
                       capture_output=True)
        (self.root / ".gitignore").write_text(".runtime/\n")
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True,
                       capture_output=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=CI",
                        "-c", "user.email=ci@example.invalid", "commit", "-m", "initial"],
                       check=True, capture_output=True)
        subprocess.run(["git", "-C", str(self.root), "remote", "add", "origin", str(remote)],
                       check=True, capture_output=True)
        subprocess.run(["git", "-C", str(self.root), "push", "-u", "origin", "main"],
                       check=True, capture_output=True)
        subprocess.run(["git", "-C", str(self.root), "remote", "set-url", "origin",
                        "https://github.com/SyameimaruKoa/My_yt-dlp_config_script.git"],
                       check=True, capture_output=True)
        (self.root / "untracked.txt").write_text("local changes\n")
        (self.root / "uninstall_yt-dlp.sh").write_text(
            (self.root / "uninstall_yt-dlp.sh").read_text() + "\n# locally modified\n"
        )
        output = self.call().stdout
        self.assertIn("リポジトリ全削除完了", output)
        self.assertFalse(self.root.exists())



if __name__ == "__main__":
    unittest.main()
