"""Build and run the standalone release without network or real configuration."""
import hashlib
import shutil
import subprocess

from test_setup import Fixture, ROOT
from test_install_mirrors import LIVE_OS_RELEASE, ORIGINAL_SCRIPT, redirect_installer_paths


class PackageTest(Fixture):
    def setUp(self):
        super().setUp()
        shutil.copytree(ROOT / "scripts", self.repo / "scripts")
        for name in ("LICENSE", "README.md", ".gitattributes"):
            shutil.copy2(ROOT / name, self.repo / name)
        subprocess.run(["git", "init", "-b", "main", str(self.repo)], env=self.env,
                       capture_output=True, check=True)
        for key, value in (("user.name", "Test"), ("user.email", "test@example.invalid")):
            subprocess.run(["git", "-C", str(self.repo), "config", key, value], env=self.env, check=True)

    def commit(self):
        subprocess.run(["git", "-C", str(self.repo), "add", "."], env=self.env, check=True)
        subprocess.run(["git", "-C", str(self.repo), "commit", "-m", "Test package"], env=self.env,
                       capture_output=True, check=True)

    def build(self, name="package"):
        output = self.base / name
        result = subprocess.run(["bash", str(self.repo / "scripts/package.sh"), str(output)],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return output / "cachyos-setup.sh"

    def run_bundle(self, script, *args, answer="", ok=True):
        result = subprocess.run(["bash", str(script), *args], env=self.env,
                                text=True, input=answer, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_standalone_contains_licenses_checksum_and_cleans_temporary_files(self):
        self.commit()
        script = self.build()
        self.assertEqual((script.parent / "SHA256SUMS").read_text().split(),
                         [hashlib.sha256(script.read_bytes()).hexdigest(), "cachyos-setup.sh"])
        self.assertIn((ROOT / "LICENSE").read_text(), script.read_text())
        self.assertIn((ROOT / "assets/kde/LICENSE.catppuccin").read_text(), script.read_text())
        self.assertEqual({p.name for p in script.parent.iterdir()}, {"cachyos-setup.sh", "SHA256SUMS"})
        shutil.rmtree(self.repo)
        temporary = self.base / "runtime temporary"
        temporary.mkdir()
        self.env["TMPDIR"] = str(temporary)
        self.assertEqual(self.run_bundle(script, "--version").stdout.strip(), self.version)
        self.assertIn("--apply", self.run_bundle(script, "--help").stdout)
        self.run_bundle(script, "--apply", "controller", answer="n\n")
        self.run_bundle(script, "--invalid", ok=False)
        self.assertFalse(self.state.exists())
        self.assertEqual(list(temporary.iterdir()), [])

    def test_standalone_installer_apply_status_and_skip_ranking(self):
        redirect_installer_paths(self.repo)
        live = self.home / "live"
        (live / "archiso").mkdir(parents=True)
        self.write(live / "etc/os-release", LIVE_OS_RELEASE)
        for name in ("mirrorlist", "cachyos-mirrorlist", "cachyos-v3-mirrorlist", "cachyos-v4-mirrorlist"):
            self.write(live / "etc/pacman.d" / name, "original\n")
        target = live / "etc/calamares/scripts/update-mirrorlist"
        self.write(target, ORIGINAL_SCRIPT)
        self.stub("sudo", 'exec "$@"')
        self.stub("pgrep", '[[ "$*" == "-x calamares" ]]')
        self.commit()
        script = self.build()
        shutil.rmtree(self.repo)
        self.run_bundle(script, "--apply", "install-mirrors", answer="y\n")
        self.assertIn("配置就绪", self.run_bundle(script, "--status", "install-mirrors").stdout)
        subprocess.run(["bash", str(target)], env=self.env, capture_output=True, check=True)

    def test_standalone_apply_status_idempotency_and_restore(self):
        self.commit()
        script = self.build()
        shutil.rmtree(self.repo)
        self.run_bundle(script, "--apply", "controller", answer="y\n")
        self.assertIn("配置就绪", self.run_bundle(script, "--status", "controller").stdout)
        original = self.gaming.read_bytes()
        self.run_bundle(script, "--apply", "proton", "--fps", "113", answer="y\n")
        self.assertEqual(self.values()["DXVK_FRAME_RATE"], "113")
        self.run_bundle(script, "--apply", "proton", answer="y\n")
        self.assertEqual(len(self.backups()), 2)
        self.run_bundle(script, "--restore", answer="y\n")
        self.assertEqual(self.gaming.read_bytes(), original)

    def fake_release_downloads(self, directory):
        self.env["TEST_RELEASE"] = str(directory)
        self.stub("curl", '''
[[ "$9" == https://github.com/Leovikii/cachyos-setup/releases/latest/download/* ]]
printf '%s\\n' "$9" >> "$HOME/downloads"
cp -- "$TEST_RELEASE/${9##*/}" "${11}"
''')

    def test_standalone_update_cancel_replace_and_latest(self):
        self.commit()
        script = self.build("local copy")
        script.chmod(0o640)
        (self.repo / "VERSION").write_text("0.1.1\n")
        self.commit()
        latest = self.build("latest")
        self.fake_release_downloads(latest.parent)
        before = script.read_bytes()
        self.run_bundle(script, "--update", answer="n\n")
        self.assertEqual(script.read_bytes(), before)
        self.run_bundle(script, "--update", answer="y\n")
        self.assertEqual(script.read_bytes(), latest.read_bytes())
        self.assertEqual(script.stat().st_mode & 0o777, 0o640)
        self.assertEqual(self.run_bundle(script, "--version").stdout.strip(), "0.1.1")
        self.assertIn("最新发行版", self.run_bundle(script, "--update").stdout)
        self.assertFalse(self.state.exists())

    def test_standalone_update_rejects_corruption_failed_download_and_symlink(self):
        self.commit()
        script = self.build()
        before = script.read_bytes()
        latest = self.base / "latest"
        latest.mkdir()
        (latest / "cachyos-setup.sh").write_text('touch "$HOME/pwned"\n')
        (latest / "SHA256SUMS").write_text("0" * 64 + "  cachyos-setup.sh\n")
        self.fake_release_downloads(latest)
        result = self.run_bundle(script, "--update", answer="y\n", ok=False)
        self.assertIn("SHA-256 校验失败", result.stderr)
        self.assertEqual(script.read_bytes(), before)
        self.assertFalse((self.home / "pwned").exists())
        self.stub("curl", 'exit 22')
        self.run_bundle(script, "--update", answer="y\n", ok=False)
        self.assertEqual(script.read_bytes(), before)
        link = script.parent / "linked.sh"
        link.symlink_to(script)
        result = self.run_bundle(link, "--update", answer="y\n", ok=False)
        self.assertIn("符号链接", result.stderr)
        self.assertEqual(script.read_bytes(), before)

    def test_release_downloader_uses_wget_without_curl(self):
        self.stub("wget", '''
[[ "$4" == https://github.com/Leovikii/cachyos-setup/releases/latest/download/cachyos-setup.sh ]]
printf 'wget download' > "$6"
''')
        target = self.base / "downloaded script"
        result = subprocess.run(["bash", "-c", '''
source "$1/lib/common.sh"
source "$1/lib/update.sh"
command() {
    if [[ "$1" == -v && "$2" == curl ]]; then return 1; fi
    builtin command "$@"
}
download_release_file cachyos-setup.sh "$2"
''', "test", str(self.repo), str(target)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(target.read_text(), "wget download")

    def test_package_rejects_invalid_committed_version(self):
        (self.repo / "VERSION").write_text("invalid\n")
        self.commit()
        result = subprocess.run(["bash", str(self.repo / "scripts/package.sh"), str(self.base / "package")],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.base / "package").exists())
