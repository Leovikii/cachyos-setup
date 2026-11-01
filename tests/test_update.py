"""Git updater tests using local repositories, without network requests."""
import shutil
import subprocess
import unittest

from test_setup import Fixture


@unittest.skipUnless(shutil.which("git"), "Git required")
class UpdateTest(Fixture):
    def setUp(self):
        super().setUp()
        self.git(self.repo, "init", "-b", "main")
        self.git(self.repo, "config", "user.name", "Test")
        self.git(self.repo, "config", "user.email", "test@example.invalid")
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "-m", "Initial")
        self.remote = self.base / "remote.git"
        self.git(self.base, "clone", "--bare", str(self.repo), str(self.remote))
        # 原始 URL 保持为受支持仓库，Git 的本地重写将请求导向临时远端。
        self.git(self.repo, "remote", "add", "origin", "https://github.com/Leovikii/cachyos-setup.git")
        self.git(self.repo, "config", f"url.{self.remote}.insteadOf", "https://github.com/Leovikii/cachyos-setup.git")
        self.git(self.repo, "fetch", "origin")
        self.git(self.repo, "branch", "--set-upstream-to=origin/main")
        self.work = self.base / "upstream"
        self.git(self.base, "clone", str(self.remote), str(self.work))
        self.git(self.work, "config", "user.name", "Test")
        self.git(self.work, "config", "user.email", "test@example.invalid")

    def git(self, directory, *args):
        return subprocess.check_output(["git", "-C", str(directory), *args], env=self.env,
                                       text=True, stderr=subprocess.STDOUT).strip()

    def publish(self, version="0.1.1"):
        (self.work / "VERSION").write_text(version + "\n")
        self.git(self.work, "add", ".")
        self.git(self.work, "commit", "-m", "Update preset")
        self.git(self.work, "push", "origin", "main")

    def test_latest_cancel_and_fast_forward_update(self):
        self.assertIn("最新提交", self.run_setup("--update").stdout)
        self.publish()
        self.run_setup("--update", answer="n\n")
        self.assertEqual(self.run_setup("--version").stdout.strip(), self.version)
        result = self.run_setup("--update", answer="y\n")
        self.assertIn("已更新至 v0.1.1", result.stdout)
        self.assertEqual(self.run_setup("--version").stdout.strip(), "0.1.1")
        self.assertFalse(self.state.exists())

    def test_dirty_worktree_and_wrong_origin_are_rejected(self):
        (self.repo / "local-notes").write_text("keep")
        self.run_setup("--update", answer="y\n", ok=False)
        (self.repo / "local-notes").unlink()
        self.git(self.repo, "remote", "set-url", "origin", str(self.remote))
        self.run_setup("--update", answer="y\n", ok=False)

    def test_divergence_never_resets_local_commits(self):
        self.publish()
        (self.repo / "local-notes").write_text("keep")
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "-m", "Local change")
        before = self.git(self.repo, "rev-parse", "HEAD")
        self.run_setup("--update", answer="y\n", ok=False)
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), before)

    def test_detached_head_invalid_version_and_incomplete_remote_are_rejected(self):
        self.git(self.repo, "checkout", "--detach")
        self.run_setup("--update", answer="y\n", ok=False)
        self.git(self.repo, "checkout", "main")
        self.publish("broken")
        self.run_setup("--update", answer="y\n", ok=False)
        (self.work / "modules/proton.sh").unlink()
        self.publish("0.1.2")
        self.run_setup("--update", answer="y\n", ok=False)
        self.assertEqual(self.run_setup("--version").stdout.strip(), self.version)
