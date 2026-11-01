"""Dependency installation uses a fake package manager; configuration is real and isolated."""
from test_setup import Fixture


class DependencyTest(Fixture):
    def setUp(self):
        super().setUp()
        self.missing_commands("python3")
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '''
printf '%s\\n' "$*" >> "$HOME/packages"
[[ "$*" == '-Syu --needed python' ]] || exit 97
touch "$HOME/dependencies-installed"
''')

    def test_preview_status_and_cancel_do_not_install_or_write(self):
        self.run_setup("--status", "proton")
        self.assertIn("python", self.run_setup("--preview", "proton").stdout)
        self.run_setup("--apply", "proton", answer="n\n")
        self.run_setup("--apply-all", "gaming", answer="\n")
        self.assertFalse((self.home / "packages").exists())
        self.assertFalse(self.config.exists())
        self.assertFalse(self.state.exists())

    def test_installs_python_once_then_applies_both_game_features(self):
        self.run_setup("--apply-all", "gaming", answer="y\n")
        self.assertEqual((self.home / "packages").read_text(), "-Syu --needed python\n")
        self.assertEqual(self.values()["DXVK_FRAME_RATE"], "117")
        self.assertEqual(self.values()["SDL_GAMECONTROLLERTYPE"], "0x37d7/0x2401=Xbox360")
        self.assertEqual(len(self.backups()), 2)
        self.run_setup("--apply-all", "gaming", answer="y\n")
        self.assertEqual(len(self.backups()), 2)

    def test_failed_or_ineffective_install_stops_before_configuration(self):
        for body in ('exit 31', 'touch "$HOME/packages"'):
            self.stub("pacman", body)
            self.run_setup("--apply-all", "gaming", answer="y\n", ok=False)
            self.assertFalse(self.config.exists())
            self.assertFalse(self.state.exists())

    def test_missing_steam_is_installed_with_python(self):
        desktop = self.source.read_text()
        self.source.unlink()
        template = self.home / "steam-template"
        template.write_text(desktop)
        self.stub("pacman", '''
printf '%s\\n' "$*" >> "$HOME/packages"
[[ "$*" == '-Syu --needed python steam' ]] || exit 97
cp "$HOME/steam-template" "$HOME/steam.desktop"
touch "$HOME/dependencies-installed"
''')
        self.run_setup("--apply", "controller", answer="n\n")
        self.assertFalse(self.source.exists())
        self.run_setup("--apply", "controller", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "controller").stdout)
        self.assertNotIn("DXVK_FRAME_RATE", self.values())

    def test_missing_sudo_is_bootstrapped_through_pkexec(self):
        self.missing_commands("sudo")
        self.stub("pkexec", 'printf "pkexec\\n" >> "$HOME/bootstrap"; exec "$@"')
        self.stub("pacman", '''
[[ "$*" == '-Syu --needed sudo python' ]] || exit 97
touch "$HOME/dependencies-installed"
''')
        self.run_setup("--apply", "controller", answer="y\n")
        self.assertEqual((self.home / "bootstrap").read_text(), "pkexec\n")
        self.assertTrue(self.helper.exists())


class BatchTest(Fixture):
    def test_each_category_menu_has_install_all_with_one_confirmation(self):
        # Exercise real menu routing, replacing only module effects to isolate menu semantics.
        for module in ("kde", "fonts", "proton", "controller", "login-screen", "install-mirrors"):
            (self.repo / "modules" / (module + ".sh")).write_text('''
feature_options() { :; }
feature_status() { printf '未配置\\n'; }
feature_preview() { printf '预览 %s\\n' "$MODULE"; }
feature_apply() { printf '%s\\n' "$MODULE" >> "$HOME/applied"; }
''')
        for index, expected in ((1, "kde\nfonts\n"), (2, "proton\ncontroller\n"),
                                (3, "login-screen\ninstall-mirrors\n")):
            result = self.run_setup(answer=f"{index}\n9\ny\n0\n0\n")
            self.assertIn("安装全部", result.stdout)
            self.assertEqual((self.home / "applied").read_text(), expected)
            (self.home / "applied").unlink()

    def test_batch_validates_all_before_applying_and_stops_on_apply_failure(self):
        self.write(self.data / "applications/steam.desktop", "unmanaged\n")
        self.run_setup("--apply-all", "gaming", answer="y\n", ok=False)
        self.assertFalse(self.gaming.exists())
        (self.data / "applications/steam.desktop").unlink()
        self.stub("install", "exit 37")
        self.run_setup("--apply-all", "gaming", answer="y\n", ok=False)
        self.assertEqual(len(self.backups()), 1)
        self.assertFalse(self.gaming.exists())

    def test_bulk_arguments_are_strict(self):
        for args in (("--apply-all",), ("--apply-all", "all"), ("--apply-all", "gaming", "extra")):
            self.run_setup(*args, ok=False)
        self.assertFalse(self.state.exists())
