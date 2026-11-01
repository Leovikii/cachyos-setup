"""Live installer files under a temporary HOME; sudo never elevates privileges."""
import subprocess

from test_setup import Fixture


ORIGINAL_SCRIPT = '''#!/usr/bin/env bash
echo "Updating rate-mirrors"
sudo pacman -Sy --noconfirm --needed cachyos-rate-mirrors rate-mirrors
sudo cachyos-rate-mirrors
'''

# CachyOS/CachyOS-Live-ISO: archiso/airootfs/etc/os-release (official Live identity).
LIVE_OS_RELEASE = 'NAME="CachyOS"\nPRETTY_NAME="CachyOS"\nID=arch\nBUILD_ID=rolling\n'
# User-reported 2026.08.09 ISO: copytoram=auto, archiso/airootfs present, no bootmnt.
COPYTORAM_OS_RELEASE = ('NAME="CachyOS Linux"\nPRETTY_NAME="CachyOS"\nID=cachyos\nID_LIKE=arch\n'
                       'IMAGE_ID=cachyos\nIMAGE_VERSION=2026.08.09\n')


def redirect_installer_paths(repo):
    module = repo / "modules/install-mirrors.sh"
    module.write_text(module.read_text().replace("INSTALL_ETC=/etc", 'INSTALL_ETC="$HOME/live/etc"')
                      .replace("INSTALL_LIVE=/run/archiso", 'INSTALL_LIVE="$HOME/live/archiso"')
                      .replace("INSTALL_PACMAN_LOCK=/var/lib/pacman/db.lck", 'INSTALL_PACMAN_LOCK="$HOME/live/db.lck"'))


class InstallMirrorsTest(Fixture):
    def setUp(self):
        super().setUp()
        redirect_installer_paths(self.repo)
        self.live = self.home / "live"
        (self.live / "archiso").mkdir(parents=True)
        self.write(self.live / "etc/os-release", COPYTORAM_OS_RELEASE)
        self.mirrors = [self.live / "etc/pacman.d" / name for name in
                        ("mirrorlist", "cachyos-mirrorlist", "cachyos-v3-mirrorlist", "cachyos-v4-mirrorlist")]
        for path in self.mirrors:
            self.write(path, "# original mirrorlist\nServer = https://example.invalid/$repo/$arch\n")
        self.script = self.live / "etc/calamares/scripts/update-mirrorlist"
        self.write(self.script, ORIGINAL_SCRIPT)
        self.script.chmod(0o750)
        self.targets = self.mirrors + [self.script]
        self.originals = [(p.read_bytes(), p.stat().st_mode & 0o777) for p in self.targets]
        self.stub("sudo", 'exec "$@"')
        self.stub("pgrep", '[[ "$*" == "-x calamares" ]]')
        for command in ("curl", "wget", "rate-mirrors", "cachyos-rate-mirrors"):
            self.stub(command, 'touch "$HOME/unexpected-network"; exit 97')

    def snapshots(self):
        return list((self.live / "etc/pacman.d").glob("cachyos-setup-install-backup.*"))

    def test_system_install_all_skips_unsupported_login_and_applies_live_feature(self):
        self.stub("readlink", 'echo /usr/lib/systemd/system/sddm.service')
        result = self.run_setup("--apply-all", "system", answer="y\n")
        self.assertIn("跳过不适用项：登录界面", result.stdout)
        self.assertIn("配置就绪", self.run_setup("--status", "install-mirrors").stdout)

    def test_missing_process_tool_is_installed_then_preflight_is_rechecked(self):
        self.missing_commands("pgrep")
        self.stub("pacman", '''
[[ "$*" == '-Syu --needed procps-ng' ]] || exit 97
touch "$HOME/dependencies-installed"
''')
        self.stub("pgrep", '[[ -e "$HOME/dependencies-installed" && "$*" == "-x calamares" ]]')
        self.run_setup("--apply", "install-mirrors", answer="n\n")
        self.assert_unchanged()
        self.run_setup("--apply", "install-mirrors", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "install-mirrors").stdout)

    def assert_unchanged(self):
        self.assertEqual([(p.read_bytes(), p.stat().st_mode & 0o777) for p in self.targets], self.originals)
        self.assertFalse(self.snapshots())
        self.assertFalse(self.state.exists())

    def test_status_preview_cancel_and_menu_never_write(self):
        self.assertIn("未配置", self.run_setup("--status", "install-mirrors").stdout)
        self.assertIn("cdn77.cachyos.org", self.run_setup("--preview", "install-mirrors").stdout)
        for answer in ("", "\n", "n\n"):
            self.run_setup("--apply", "install-mirrors", answer=answer)
        result = self.run_setup(answer="3\n2\nn\n0\n0\n")
        self.assertIn("安装跳过测速", result.stdout)
        self.assert_unchanged()

    def test_official_live_identity_without_bootmnt_is_supported(self):
        (self.live / "etc/os-release").write_text(LIVE_OS_RELEASE)
        self.assertFalse((self.live / "archiso/bootmnt").exists())
        self.assertIn("未配置", self.run_setup("--status", "install-mirrors").stdout)
        self.run_setup("--apply", "install-mirrors", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "install-mirrors").stdout)

    def test_reported_copytoram_live_without_bootmnt_is_supported(self):
        (self.live / "archiso/airootfs").mkdir()
        self.assertFalse((self.live / "archiso/bootmnt").exists())
        self.assertIn("未配置", self.run_setup("--status", "install-mirrors").stdout)
        self.run_setup("--preview", "install-mirrors")
        self.run_setup("--apply", "install-mirrors", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "install-mirrors").stdout)

    def test_identity_variants_and_other_arch_live_images(self):
        release = self.live / "etc/os-release"
        for identity in (LIVE_OS_RELEASE, 'ID=cachyos\n', 'ID="cachyos"\n',
                         "ID='cachyos'\n", "ID='arch'\nNAME='CachyOS'\n",
                         'ID="arch"\nNAME="CachyOS Linux"\n'):
            with self.subTest(identity=identity):
                release.write_text(identity)
                self.assertIn("未配置", self.run_setup("--status", "install-mirrors").stdout)
                self.run_setup("--preview", "install-mirrors")
        for identity in ('ID=arch\nNAME="Arch Linux"\n', 'ID=other\nNAME="CachyOS"\n',
                         'ID_LIKE=arch\nNAME="CachyOS"\n'):
            with self.subTest(identity=identity):
                release.write_text(identity)
                self.assertIn("不适用", self.run_setup("--status", "install-mirrors").stdout)
                self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        self.assert_unchanged()

    def test_unreadable_identity_is_reported_without_executing_it(self):
        release = self.live / "etc/os-release"
        release.chmod(0)
        self.assertIn("无法检查", self.run_setup("--status", "install-mirrors").stdout)
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        release.chmod(0o644)
        release.write_text(LIVE_OS_RELEASE + 'IGNORED=$(touch "$HOME/executed-os-release")\n')
        self.run_setup("--preview", "install-mirrors")
        self.assertFalse((self.home / "executed-os-release").exists())
        self.assert_unchanged()

    def test_apply_skips_ranking_preserves_variables_and_is_idempotent(self):
        result = self.run_setup("--apply", "install-mirrors", answer="yes\n")
        self.assertEqual(result.stdout.count("sudo cp -a --"), 5)
        expected = ["https://archlinux.cachyos.org/repo/$repo/os/$arch",
                    "https://cdn77.cachyos.org/repo/$arch/$repo",
                    "https://cdn77.cachyos.org/repo/$arch_v3/$repo",
                    "https://cdn77.cachyos.org/repo/$arch_v4/$repo"]
        for path, url in zip(self.mirrors, expected):
            self.assertEqual(path.read_text(), f"Server = {url}\n")
            self.assertEqual(path.stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.script.stat().st_mode & 0o777, 0o755)
        subprocess.run(["bash", str(self.script)], env=self.env, capture_output=True, check=True)
        self.assertFalse((self.home / "unexpected-network").exists())
        self.assertIn("配置就绪", self.run_setup("--status", "install-mirrors").stdout)
        before = [(p.read_bytes(), p.stat().st_mtime_ns) for p in self.targets]
        self.run_setup("--apply", "install-mirrors", answer="y\n")
        self.assertEqual([(p.read_bytes(), p.stat().st_mtime_ns) for p in self.targets], before)
        self.assertEqual(len(self.snapshots()), 1)
        self.mirrors[2].write_text("Server = https://changed.invalid\n")
        self.assertIn("配置不完整", self.run_setup("--status", "install-mirrors").stdout)
        self.run_setup("--apply", "install-mirrors", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "install-mirrors").stdout)

    def test_backup_and_printed_commands_restore_bytes_and_permissions(self):
        result = self.run_setup("--apply", "install-mirrors", answer="y\n")
        backup, = self.snapshots()
        for index, original in enumerate(self.originals):
            saved = backup / str(index)
            self.assertEqual((saved.read_bytes(), saved.stat().st_mode & 0o777), original)
        commands = "\n".join(line for line in result.stdout.splitlines() if line.startswith("sudo cp -a --"))
        subprocess.run(["bash", "-e", "-c", commands], env=self.env, capture_output=True, check=True)
        self.assertEqual([(p.read_bytes(), p.stat().st_mode & 0o777) for p in self.targets], self.originals)
        self.assertIn("未配置", self.run_setup("--status", "install-mirrors").stdout)

    def test_installed_system_wrong_distro_missing_files_and_options_are_rejected(self):
        self.run_setup("--preview", "install-mirrors", "--unknown", ok=False)
        (self.live / "archiso").rmdir()
        self.assertIn("不适用", self.run_setup("--status", "install-mirrors").stdout)
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        (self.live / "archiso").mkdir()
        (self.live / "etc/os-release").write_text("ID=arch\n")
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        (self.live / "etc/os-release").write_text("ID=cachyos\n")
        original = self.script.read_bytes()
        self.script.unlink()
        self.assertIn("无法检查", self.run_setup("--status", "install-mirrors").stdout)
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        self.script.write_bytes(original)
        self.script.chmod(0o750)
        self.assert_unchanged()

    def test_unknown_script_and_symlink_paths_are_protected(self):
        self.script.write_text(ORIGINAL_SCRIPT + "echo custom\n")
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        self.assertTrue(self.script.read_text().endswith("echo custom\n"))
        self.script.write_text(ORIGINAL_SCRIPT)
        outside = self.home / "outside"
        outside.write_text("keep\n")
        self.mirrors[0].unlink()
        self.mirrors[0].symlink_to(outside)
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        self.assertEqual(outside.read_text(), "keep\n")
        self.assertFalse(self.snapshots())
        self.assertFalse(self.state.exists())

    def test_unreadable_file_and_symlink_parent_are_protected(self):
        self.mirrors[0].chmod(0)
        self.assertIn("无法检查", self.run_setup("--status", "install-mirrors").stdout)
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        self.mirrors[0].chmod(0o644)
        directory = self.mirrors[0].parent
        outside = self.home / "outside-mirrors"
        directory.rename(outside)
        directory.symlink_to(outside, target_is_directory=True)
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        self.assertEqual([p.read_bytes() for p in self.targets], [b for b, _ in self.originals])
        self.assertFalse(list(outside.glob("cachyos-setup-install-backup.*")))
        self.assertFalse(self.state.exists())

    def test_installer_not_open_or_pacman_locked_never_writes(self):
        self.stub("pgrep", "exit 1")
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        self.stub("pgrep", '[[ "$*" == "-x calamares" ]]')
        self.write(self.live / "db.lck", "")
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        self.assert_unchanged()

    def test_privileged_recheck_rejects_changed_script_before_backup(self):
        self.stub("sudo", 'printf "echo replaced\\n" > "$HOME/live/etc/calamares/scripts/update-mirrorlist"; exec "$@"')
        self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        self.assertEqual(self.script.read_text(), "echo replaced\n")
        self.assertFalse(self.snapshots())
        self.assertEqual([p.read_bytes() for p in self.mirrors], [b for b, _ in self.originals[:4]])

    def test_write_failure_retains_backups_and_cleans_staging_files(self):
        self.stub("mv", '''
if [[ -f "$HOME/moved-once" ]]; then exit 29; fi
touch "$HOME/moved-once"
exec /usr/bin/mv "$@"
''')
        result = self.run_setup("--apply", "install-mirrors", answer="y\n", ok=False)
        self.assertNotIn("已应用安装跳过测速", result.stdout)
        self.assertIn("sudo cp -a --", result.stdout)
        backup, = self.snapshots()
        for index, (content, _) in enumerate(self.originals):
            self.assertEqual((backup / str(index)).read_bytes(), content)
        self.assertFalse(list(self.live.rglob(".cachyos-setup-*")))
        self.assertNotEqual(self.mirrors[0].read_bytes(), self.originals[0][0])
        self.assertEqual(self.script.read_bytes(), self.originals[4][0])
        commands = "\n".join(line for line in result.stdout.splitlines() if line.startswith("sudo cp -a --"))
        subprocess.run(["bash", "-e", "-c", commands], env=self.env, capture_output=True, check=True)
        self.assertEqual([p.read_bytes() for p in self.targets], [b for b, _ in self.originals])
