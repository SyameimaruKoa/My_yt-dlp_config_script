import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(os.name == "posix" and shutil.which("git"), "Linux Git test")
class LegacyCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = pathlib.Path(self.temp.name)
        self.gist = self.home / "21141912fbacf40877f4cf877577e082"
        self.script = pathlib.Path(__file__).resolve().parents[1] / "tools/migration/remove-standalone.sh"
        self.env = dict(os.environ, HOME=str(self.home), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        self.remote = self.home / "remote.git"
        source = self.home / "source"
        self.git("init", "--bare", "-b", "main", str(self.remote))
        self.git("init", "-b", "main", str(source))
        (source / "yt-dlp config").write_text("test config\n", encoding="utf-8")
        (source / ".gitignore").write_text("win yt-dlp config\n", encoding="utf-8")
        self.git("-C", str(source), "add", ".")
        self.git("-C", str(source), "-c", "user.name=CI", "-c", "user.email=ci@example.invalid", "commit", "-m", "initial")
        self.git("-C", str(source), "remote", "add", "origin", str(self.remote))
        self.git("-C", str(source), "push", "-u", "origin", "main")
        self.git("clone", str(self.remote), str(self.gist))
        self.git("-C", str(self.gist), "remote", "set-url", "origin", "https://gist.github.com/21141912fbacf40877f4cf877577e082.git")

    def git(self, *args):
        return subprocess.run(["git", *args], env=self.env, check=True, text=True, capture_output=True)

    def cleanup(self, dry_run=False):
        args = ["bash", str(self.script), "--path", str(self.home / "absent"), "--legacy-gist"]
        if dry_run:
            args.append("--dry-run")
        return subprocess.run(args, env=self.env, check=True, text=True, capture_output=True)

    def test_clean_clone_removed_only_after_dry_run(self):
        self.assertIn("旧Gist全削除予定", self.cleanup(dry_run=True).stdout)
        self.assertTrue(self.gist.exists())
        self.assertIn("旧Gist削除完了", self.cleanup().stdout)
        self.assertFalse(self.gist.exists())

    def test_known_ignored_generated_config_is_removed(self):
        (self.gist / "win yt-dlp config").write_text("generated\n", encoding="utf-8")
        self.assertIn("旧Gist削除完了", self.cleanup().stdout)
        self.assertFalse(self.gist.exists())

    def test_modified_file_is_deleted(self):
        (self.gist / "yt-dlp config").write_text("local change\n", encoding="utf-8")
        self.assertIn("旧Gist削除完了", self.cleanup().stdout)
        self.assertFalse(self.gist.exists())

    def test_untracked_file_is_deleted(self):
        (self.gist / "private.txt").write_text("keep\n", encoding="utf-8")
        self.assertIn("旧Gist削除完了", self.cleanup().stdout)
        self.assertFalse(self.gist.exists())

    def test_unpushed_commit_is_deleted(self):
        (self.gist / "yt-dlp config").write_text("local commit\n", encoding="utf-8")
        self.git("-C", str(self.gist), "add", ".")
        self.git("-C", str(self.gist), "-c", "user.name=CI", "-c", "user.email=ci@example.invalid", "commit", "-m", "local")
        self.assertIn("旧Gist削除完了", self.cleanup().stdout)
        self.assertFalse(self.gist.exists())

    def test_wrong_remote_is_deleted(self):
        self.git("-C", str(self.gist), "remote", "set-url", "origin", str(self.remote))
        self.assertIn("旧Gist削除完了", self.cleanup().stdout)
        self.assertFalse(self.gist.exists())

    def test_symlink_itself_is_deleted_without_following_target(self):
        destination = self.home / "linked-repo"
        self.gist.rename(destination)
        self.gist.symlink_to(destination, target_is_directory=True)
        self.assertIn("旧Gist削除完了", self.cleanup().stdout)
        self.assertFalse(self.gist.is_symlink())
        self.assertTrue(destination.exists())


if __name__ == "__main__":
    unittest.main()
