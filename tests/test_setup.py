"""Isolated HOME and command stubs: never install packages or modify the desktop."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cachyos-test-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        self.repo.mkdir()
        for name in ("lib", "modules", "assets"):
            shutil.copytree(ROOT / name, self.repo / name)
        for name in ("setup.sh", "VERSION"):
            shutil.copy2(ROOT / name, self.repo / name)
        self.version = (self.repo / "VERSION").read_text().strip()
        self.home = self.base / "test home"
        self.home.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.config = self.home / "config"
        self.data = self.home / "data"
        self.state = self.home / "state/cachyos-setup"
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                        XDG_DATA_HOME=str(self.data), XDG_STATE_HOME=str(self.home / "state"),
                        XDG_CACHE_HOME=str(self.home / "cache"), XDG_CONFIG_DIRS=str(self.home / "system-config"),
                        XDG_DATA_DIRS=str(self.home / "system-data"), XDG_CURRENT_DESKTOP="test",
                        PATH=f"{self.bin}:{os.environ['PATH']}", QT_QPA_PLATFORM="offscreen",
                        DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent-cachyos-test")
        self.source = self.home / "steam.desktop"
        self.source.write_text("[Desktop Entry]\nType=Application\nName=Steam\nExec=/usr/bin/steam %U\n"
                               "Actions=Library;\n[Desktop Action Library]\nName=Library\n"
                               "Exec=/usr/bin/steam steam://open/games\n")
        module = self.repo / "modules/gaming.sh"
        module.write_text(module.read_text().replace("DESKTOP_SOURCE=/usr/share/applications/steam.desktop",
                                                    'DESKTOP_SOURCE="$HOME/steam.desktop"'))
        for name in ("pacman", "paru", "yay", "sudo", "systemctl", "udevadm"):
            self.stub(name, 'echo "unexpected system command" >&2; exit 97')
        for name in ("fc-cache", "kbuildsycoca6", "dbus-update-activation-environment"):
            self.stub(name, 'printf "%s\\n" "$0 $*" >> "$HOME/actions"')
        self.gaming = self.config / "environment.d/90-cachyos-gaming.conf"
        self.helper = self.home / ".local/bin/steam-managed"

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -e\n" + body + "\n")
        path.chmod(0o755)

    def missing_commands(self, *names):
        """Hide discovery and reject execution until the fake package install succeeds."""
        self.hidden_commands = sorted(set(getattr(self, "hidden_commands", ())) | set(names))
        common = self.repo / "lib/common.sh"
        common.write_text(common.read_text() + '''
command() {
    if [[ "$1" == -v && ! -e "$HOME/dependencies-installed" ]]; then
        case "$2" in ''' + "|".join(self.hidden_commands) + ''') return 1 ;; esac
    fi
    builtin command "$@"
}
''')
        for name in names:
            real = shutil.which(name)
            if real:
                import shlex
                self.stub(name, '[[ -e "$HOME/dependencies-installed" ]] || exit 96\n'
                          + 'exec ' + shlex.quote(real) + ' "$@"')

    def run_setup(self, *args, answer="", ok=True):
        result = subprocess.run(["bash", str(self.repo / "setup.sh"), *args], env=self.env,
                                text=True, input=answer, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def values(self):
        return dict(line.split("=", 1) for line in self.gaming.read_text().splitlines()
                    if line and not line.startswith("#"))

    def backups(self):
        return list((self.state / "backups").glob("*"))


class SetupTest(Fixture):
    def test_menu_eof_navigation_and_cancel_never_write(self):
        for answer in ("", "0\n", "1\n0\n2\n0\n3\n0\n0\n", "2\n1\nn\n0\n0\n"):
            self.run_setup(answer=answer)
            self.assertFalse(self.config.exists())
            self.assertFalse(self.data.exists())
            self.assertFalse(self.state.exists())

    def test_version_help_and_invalid_arguments(self):
        self.assertEqual(self.run_setup("--version").stdout.strip(), self.version)
        self.assertIn("--apply", self.run_setup("--help").stdout)
        for args in (("--apply",), ("--apply", "invalid"), ("--migrate",), ("--apply", "migration"), ("--status", "fonts", "extra"),
                     ("--apply", "proton", "--fps", "0"), ("--apply", "fonts", "--size", "20"),
                     ("--apply", "controller", "--fps", "117")):
            self.run_setup(*args, ok=False)
        self.assertFalse(self.state.exists())

    def test_proton_install_status_custom_values_and_idempotency(self):
        self.run_setup("--apply", "proton", "--fps", "113", "--no-anti-lag-layer", answer="y\n")
        self.assertEqual(self.values()["DXVK_FRAME_RATE"], "113")
        self.assertNotIn("LOW_LATENCY_LAYER", self.values())
        before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.home.rglob("*") if p.is_file()}
        self.run_setup("--apply", "proton", answer="yes\n")
        self.assertEqual(len(self.backups()), 1)
        for p, content in before.items():
            if p.name != "lock":
                self.assertEqual((p.read_bytes(), p.stat().st_mtime_ns), content, str(p))
        self.assertIn("配置就绪（113 FPS", self.run_setup("--status", "proton").stdout)
        self.helper.chmod(0o644)
        self.assertIn("配置不完整", self.run_setup("--status", "proton").stdout)
        self.run_setup("--apply", "proton", answer="y\n")
        self.assertTrue(os.access(self.helper, os.X_OK))

    def test_controller_only_and_shared_config_preservation(self):
        self.run_setup("--apply", "controller", answer="y\n")
        self.assertEqual(self.values(), {"SDL_GAMECONTROLLERTYPE": "0x37d7/0x2401=Xbox360"})
        self.assertIn("未配置", self.run_setup("--status", "proton").stdout)
        self.run_setup("--apply", "proton", "--fps", "115", answer="y\n")
        self.run_setup("--apply", "controller", answer="y\n")
        self.assertEqual(self.values()["DXVK_FRAME_RATE"], "115")
        self.assertEqual(self.values()["SDL_GAMECONTROLLERTYPE"], "0x37d7/0x2401=Xbox360")

    def test_launcher_and_kde_read_saved_values_and_forward_uri(self):
        self.run_setup("--apply", "proton", answer="y\n")
        self.gaming.write_text(self.gaming.read_text().replace("=117", "=111"))
        self.helper.write_text(self.helper.read_text().replace('exec /usr/bin/steam "$@"',
            "exec python3 -c 'import json,os,sys;print(json.dumps([dict(os.environ),sys.argv[1:]]))' \"$@\""))
        result = subprocess.run([str(self.helper), "steam://open/games"], env=dict(self.env, DXVK_HDR="1"),
                                text=True, capture_output=True, check=True)
        env, args = json.loads(result.stdout)
        self.assertEqual(env["DXVK_FRAME_RATE"], "111")
        self.assertNotIn("DXVK_HDR", env)
        self.assertEqual(args, ["steam://open/games"])
        kde = self.config / "plasma-workspace/env/gaming-env.sh"
        result = subprocess.run(["sh", "-c", '. "$1"; env', "test", str(kde)], env=self.env,
                                text=True, capture_output=True, check=True)
        self.assertIn("DXVK_FRAME_RATE=111\n", result.stdout)

    def test_controller_loader_preserves_unrelated_proton_environment(self):
        self.run_setup("--apply", "controller", answer="y\n")
        kde = self.config / "plasma-workspace/env/gaming-env.sh"
        result = subprocess.run(["sh", "-c", '. "$1"; env', "test", str(kde)],
                                env=dict(self.env, PROTON_ENABLE_WAYLAND="0", DXVK_HDR="1"),
                                text=True, capture_output=True, check=True)
        self.assertIn("PROTON_ENABLE_WAYLAND=0\n", result.stdout)
        self.assertIn("DXVK_HDR=1\n", result.stdout)

    def test_invalid_configuration_cannot_execute_or_mutate(self):
        self.write(self.gaming, f"# Managed by cachyos-setup\nDXVK_FRAME_RATE=$(touch '{self.home}/pwned')\n")
        before = self.gaming.read_bytes()
        self.run_setup("--apply", "controller", answer="y\n", ok=False)
        self.assertEqual(self.gaming.read_bytes(), before)
        self.assertFalse(self.state.exists())
        self.assertFalse((self.home / "pwned").exists())
        self.assertIn("配置不完整", self.run_setup("--status", "proton").stdout)

    def test_unknown_files_and_symlinks_are_protected(self):
        desktop = self.data / "applications/steam.desktop"
        self.write(desktop, "custom desktop\n")
        self.run_setup("--apply", "proton", answer="y\n", ok=False)
        self.assertEqual(desktop.read_text(), "custom desktop\n")
        desktop.unlink()
        external = self.home / "outside"
        external.mkdir()
        self.config.symlink_to(external, target_is_directory=True)
        self.run_setup("--apply", "controller", answer="y\n", ok=False)
        self.assertEqual(list(external.iterdir()), [])

    def test_restore_preview_cancel_and_originally_absent_files(self):
        self.run_setup("--apply", "proton", answer="y\n")
        self.run_setup("--restore", answer="\n")
        self.assertTrue(self.gaming.exists())
        self.run_setup("--restore", answer="y\n")
        self.assertFalse(self.gaming.exists())
        self.assertFalse(self.helper.exists())

    def test_shared_config_restore_keeps_previous_module(self):
        self.run_setup("--apply", "controller", answer="y\n")
        original = self.gaming.read_bytes()
        self.run_setup("--apply", "proton", answer="y\n")
        self.run_setup("--restore", answer="y\n")
        self.assertEqual(self.gaming.read_bytes(), original)
        self.assertTrue(self.helper.exists())

    def test_backup_path_tampering_is_rejected(self):
        self.run_setup("--apply", "proton", answer="y\n")
        backup = self.backups()[0]
        (backup / "targets").write_text("/etc/passwd\n")
        self.run_setup("--restore", answer="y\n", ok=False)
        self.assertTrue(self.gaming.exists())

    def test_low_latency_conflict_and_toggle(self):
        self.run_setup("--apply", "proton", "--dx12-lowlatency", "--anti-lag-layer", ok=False)
        self.run_setup("--apply", "proton", "--dx12-lowlatency", answer="y\n")
        self.assertNotIn("LOW_LATENCY_LAYER", self.values())
        self.run_setup("--apply", "proton", "--no-dx12-lowlatency", "--anti-lag-layer", answer="y\n")
        self.assertNotIn("PROTON_VKD3D_LOWLATENCY", self.values())
        self.assertEqual(self.values()["LOW_LATENCY_LAYER"], "1")


if __name__ == "__main__":
    unittest.main()
