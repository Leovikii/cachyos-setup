"""Native KConfig in a temporary HOME, with package/desktop commands replaced."""
import json
import os
import shutil
import unittest
import xml.etree.ElementTree as ET

from test_setup import Fixture


@unittest.skipUnless(shutil.which("kreadconfig6") and shutil.which("kwriteconfig6"), "KConfig 6 tools required")
class DesktopTest(Fixture):
    def setUp(self):
        super().setUp()
        self.env.update(XDG_CURRENT_DESKTOP="KDE", KDE_SESSION_VERSION="6", XDG_SESSION_TYPE="wayland")
        self.stub("qtpaths6", 'printf "%s\\n" "$HOME/plugins"')
        self.stub("qdbus6", 'printf "dbus %s\\n" "$*" >> "$HOME/actions"')
        self.stub("plasma-apply-colorscheme", '''
if [[ "$1" != --accent-color ]]; then
    kwriteconfig6 --file "$XDG_CONFIG_HOME/kdeglobals" --group General --key ColorScheme "$1"
fi
kwriteconfig6 --file "$XDG_CONFIG_HOME/kdeglobals" --group Colors:Window --key BackgroundNormal 24,24,37
''')
        self.stub("plasma-apply-desktoptheme", 'kwriteconfig6 --file "$XDG_CONFIG_HOME/plasmarc" --group Theme --key name "$1"')
        self.stub("plasma-apply-cursortheme", '''
kwriteconfig6 --file "$XDG_CONFIG_HOME/kcminputrc" --group Mouse --key cursorTheme "$1"
kwriteconfig6 --file "$XDG_CONFIG_HOME/kcminputrc" --group Mouse --key cursorSize 24
''')
        self.stub("fc-list", "printf '%s\\n' 'Sarasa UI SC' 'Sarasa Term SC' 'Noto Serif CJK SC' 'Noto Color Emoji'")
        for name in ("styles/breeze6.so", "org.kde.kdecoration3/org.kde.breeze.so", "org.kde.kdecoration3/org.kde.klassy.so"):
            self.write(self.home / "plugins" / name, "fixture")
        for name in ("plasma/desktoptheme/default/metadata.json", "icons/Papirus-Dark/index.theme",
                     "icons/Bibata-Modern-Ice/index.theme", "icons/Bibata-Modern-Ice/cursors/left_ptr"):
            self.write(self.data / name, "fixture")

    def test_kde_applies_preserves_size_is_idempotent_and_restores(self):
        original = "[General]\nfont=CustomFont\n[KDE]\nwidgetStyle=Custom\n"
        self.write(self.config / "kdeglobals", original)
        self.write(self.config / "kcminputrc", "[Mouse]\ncursorSize=48\n")
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertIn("cursorSize=48", (self.config / "kcminputrc").read_text())
        self.assertIn("font=CustomFont", (self.config / "kdeglobals").read_text())
        self.assertIn("配置就绪", self.run_setup("--status", "kde").stdout)
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertEqual(len(self.backups()), 1)
        self.run_setup("--restore", answer="y\n")
        self.assertEqual((self.config / "kdeglobals").read_text(), original)
        self.assertFalse((self.data / "color-schemes/CatppuccinMochaPink.colors").exists())

    def test_kde_incompatible_plugin_never_applies_theme(self):
        (self.home / "plugins/org.kde.kdecoration3/org.kde.klassy.so").unlink()
        self.stub("pacman", 'if [[ "$1" == -Q ]]; then exit 0; fi; exit 97')
        self.run_setup("--apply", "kde", answer="y\n", ok=False)
        self.assertFalse((self.config / "kdeglobals").exists())

    def test_kde_reinstalls_installed_but_unavailable_decoration(self):
        (self.home / "plugins/org.kde.kdecoration3/org.kde.klassy.so").unlink()
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '''
case "$1" in
    -Q|-Si) [[ "$2" == klassy ]] ;;
    -Syu)
        [[ "$*" == '-Syu klassy' ]]
        touch "$HOME/plugins/org.kde.kdecoration3/org.kde.klassy.so"
        printf '%s\\n' "$*" >> "$HOME/packages" ;;
    *) exit 97 ;;
esac
''')
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertEqual((self.home / "packages").read_text(), "-Syu klassy\n")
        self.assertIn("配置就绪", self.run_setup("--status", "kde").stdout)

    def test_kde_rebuilds_installed_aur_decoration_against_current_abi(self):
        (self.home / "plugins/org.kde.kdecoration3/org.kde.klassy.so").unlink()
        self.write(self.home / "plugins/org.kde.kdecoration2/org.kde.klassy.so", "old ABI")
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '''
case "$1" in
    -Q) [[ "$2" == klassy ]] ;;
    -Si) exit 1 ;;
    -Syu) [[ "$*" == '-Syu base-devel git' ]] ;;
    *) exit 97 ;;
esac
''')
        self.stub("paru", '''
[[ "$*" == '-Syu --rebuild klassy' ]]
touch "$HOME/plugins/org.kde.kdecoration3/org.kde.klassy.so"
''')
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "kde").stdout)

    def test_kde_installs_missing_repo_components_only_once(self):
        (self.home / "plugins/org.kde.kdecoration3/org.kde.klassy.so").unlink()
        (self.data / "icons/Papirus-Dark/index.theme").unlink()
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '''
printf 'pacman %s\\n' "$*" >> "$HOME/actions"
case "$1" in
    -Q) exit 1 ;;
    -Si) exit 0 ;;
    -Syu)
        touch "$HOME/plugins/org.kde.kdecoration3/org.kde.klassy.so"
        touch "$XDG_DATA_HOME/icons/Papirus-Dark/index.theme" ;;
    *) exit 97 ;;
esac
''')
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "kde").stdout)
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertEqual((self.home / "actions").read_text().count("pacman -Syu --needed klassy papirus-icon-theme"), 1)

    def test_kde_uses_existing_aur_helper_when_repo_package_is_missing(self):
        (self.home / "plugins/org.kde.kdecoration3/org.kde.klassy.so").unlink()
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '[[ "$*" == "-Syu --needed base-devel git" ]]')
        self.stub("paru", '''
printf 'paru %s\\n' "$*" >> "$HOME/actions"
[[ "$*" == '-Syu --needed klassy' ]] || exit 97
touch "$HOME/plugins/org.kde.kdecoration3/org.kde.klassy.so"
''')
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "kde").stdout)
        self.assertIn("paru -Syu --needed klassy", (self.home / "actions").read_text())

    def test_missing_aur_helper_and_build_dependencies_are_installed_automatically(self):
        (self.home / "plugins/org.kde.kdecoration3/org.kde.klassy.so").unlink()
        self.missing_commands("paru", "yay")
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '''
[[ "$*" == '-Syu --needed paru base-devel git' ]] || exit 1
printf '%s\\n' "$*" >> "$HOME/packages"
touch "$HOME/dependencies-installed"
''')
        self.stub("paru", '''
[[ -e "$HOME/dependencies-installed" && "$*" == '-Syu --needed klassy' ]]
touch "$HOME/plugins/org.kde.kdecoration3/org.kde.klassy.so"
''')
        self.run_setup("--apply", "kde", answer="n\n")
        self.assertFalse((self.home / "packages").exists())
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "kde").stdout)

    def test_missing_font_tools_are_installed_before_reading_and_preserve_settings(self):
        self.run_setup("--apply", "fonts", "--size", "13", "--rgba", "bgr", answer="y\n")
        self.missing_commands("python3", "kwriteconfig6")
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '''
[[ "$*" == '-Syu --needed python kconfig' ]] || exit 97
touch "$HOME/dependencies-installed"
''')
        self.run_setup("--apply", "fonts", answer="y\n")
        self.assertIn("配置就绪（13pt / bgr）", self.run_setup("--status", "fonts").stdout)

    def test_desktop_install_all_applies_kde_and_fonts(self):
        self.run_setup("--apply-all", "desktop", answer="y\n")
        for module in ("kde", "fonts"):
            self.assertIn("配置就绪", self.run_setup("--status", module).stdout)

    def test_kde_installs_missing_qt_tools_before_applying(self):
        self.missing_commands("kwriteconfig6", "qdbus6")
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '''
[[ "$*" == '-Syu --needed kconfig qt6-tools' ]] || exit 97
touch "$HOME/dependencies-installed"
''')
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "kde").stdout)

    def test_ready_desktop_does_not_install_unused_apply_tools(self):
        self.run_setup("--apply-all", "desktop", answer="y\n")
        self.missing_commands("kwriteconfig6", "qdbus6")
        self.run_setup("--apply-all", "desktop", answer="y\n")
        self.assertFalse((self.home / "dependencies-installed").exists())
        self.assertEqual(len(self.backups()), 2)

    def test_qt_tool_outside_path_is_used_without_installing_extra_packages(self):
        self.missing_commands("qtpaths6")
        fallback = self.home / "qtpaths"
        fallback.write_text('#!/bin/bash\nprintf "%s\\n" "$HOME/plugins"\n')
        fallback.chmod(0o755)
        module = self.repo / "modules/kde.sh"
        module.write_text(module.read_text().replace('/usr/lib/qt6/bin/qtpaths6', '"$HOME/qtpaths"'))
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertFalse((self.home / "dependencies-installed").exists())
        self.assertIn("配置就绪", self.run_setup("--status", "kde").stdout)

    def test_existing_aur_build_tools_are_not_reinstalled(self):
        (self.home / "plugins/org.kde.kdecoration3/org.kde.klassy.so").unlink()
        self.stub("pacman", '''
case "$1" in
    -Q) [[ "$2" == base-devel || "$2" == git ]] ;;
    -Si) exit 1 ;;
    *) printf 'unexpected install\\n' >> "$HOME/packages"; exit 97 ;;
esac
''')
        self.stub("paru", '''
[[ "$*" == '-Syu --needed klassy' ]]
touch "$HOME/plugins/org.kde.kdecoration3/org.kde.klassy.so"
''')
        self.run_setup("--apply", "kde", answer="y\n")
        self.assertFalse((self.home / "packages").exists())
        self.assertIn("配置就绪", self.run_setup("--status", "kde").stdout)

    def test_kde_apply_failure_keeps_recoverable_snapshot(self):
        self.write(self.config / "kdeglobals", "[General]\nColorScheme=Before\n")
        self.stub("plasma-apply-colorscheme", "exit 29")
        self.run_setup("--apply", "kde", answer="y\n", ok=False)
        self.assertEqual(len(self.backups()), 1)
        self.run_setup("--restore", answer="y\n")
        self.assertEqual((self.config / "kdeglobals").read_text(), "[General]\nColorScheme=Before\n")

    def test_fonts_xml_size_preservation_idempotency_and_restore(self):
        self.write(self.config / "kdeglobals", "[General]\nColorScheme=Keep\n")
        self.run_setup("--apply", "fonts", "--size", "12", "--rgba", "rgb", answer="y\n")
        file = self.config / "fontconfig/conf.d/60-cachyos-fonts.conf"
        tree = ET.fromstring(file.read_text())
        aliases = {node.findtext("family"): node.findtext("prefer/family") for node in tree.findall("alias")}
        self.assertEqual(aliases["sans-serif"], "Sarasa UI SC")
        self.assertEqual(aliases["emoji"], "Noto Color Emoji")
        self.assertIn("ColorScheme=Keep", (self.config / "kdeglobals").read_text())
        self.assertIn("配置就绪（12pt / rgb）", self.run_setup("--status", "fonts").stdout)
        self.run_setup("--apply", "fonts", answer="y\n")
        self.assertEqual(len(self.backups()), 1)
        self.run_setup("--restore", answer="y\n")
        self.assertFalse(file.exists())
        self.assertEqual((self.config / "kdeglobals").read_text(), "[General]\nColorScheme=Keep\n")

    def test_fonts_install_failure_does_not_write_configuration(self):
        self.stub("fc-list", "exit 0")
        self.run_setup("--apply", "fonts", answer="y\n", ok=False)
        self.assertFalse((self.config / "fontconfig/conf.d/60-cachyos-fonts.conf").exists())
        self.assertFalse(self.backups())

    def test_fonts_installs_missing_packages_and_applies_configuration(self):
        self.stub("fc-list", '''
[[ -f "$HOME/fonts-installed" ]] || exit 0
printf '%s\\n' 'Sarasa UI SC' 'Sarasa Term SC' 'Noto Serif CJK SC' 'Noto Color Emoji'
''')
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '''
printf 'pacman %s\\n' "$*" >> "$HOME/actions"
[[ "$*" == '-Syu --needed ttf-sarasa-gothic noto-fonts-cjk noto-fonts-emoji' ]] || exit 97
touch "$HOME/fonts-installed"
''')
        self.run_setup("--apply", "fonts", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "fonts").stdout)
        self.run_setup("--apply", "fonts", answer="y\n")
        self.assertEqual((self.home / "actions").read_text().count("pacman -Syu"), 1)

    def test_fonts_reinstall_when_package_exists_but_font_families_are_missing(self):
        self.stub("fc-list", '''
[[ -e "$HOME/fonts-reinstalled" ]] || exit 0
printf '%s\\n' 'Sarasa UI SC' 'Sarasa Term SC' 'Noto Serif CJK SC' 'Noto Color Emoji'
''')
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '''
if [[ "$1" == -Q ]]; then exit 0; fi
[[ "$*" == '-Syu ttf-sarasa-gothic noto-fonts-cjk noto-fonts-emoji' ]]
touch "$HOME/fonts-reinstalled"
''')
        self.run_setup("--apply", "fonts", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "fonts").stdout)

    def test_fonts_install_only_the_missing_font_family_package(self):
        self.stub("fc-list", '''
printf '%s\\n' 'Sarasa UI SC' 'Sarasa Term SC' 'Noto Color Emoji'
[[ ! -e "$HOME/cjk-installed" ]] || printf 'Noto Serif CJK SC\\n'
''')
        self.stub("sudo", 'exec "$@"')
        self.stub("pacman", '''
[[ "$1" != -Q ]] || exit 1
[[ "$*" == '-Syu --needed noto-fonts-cjk' ]]
printf '%s\\n' "$*" >> "$HOME/packages"
touch "$HOME/cjk-installed"
''')
        self.run_setup("--apply", "fonts", answer="y\n")
        self.assertEqual((self.home / "packages").read_text(), "-Syu --needed noto-fonts-cjk\n")
        self.assertIn("配置就绪", self.run_setup("--status", "fonts").stdout)

    def test_font_formatting_comments_and_redundant_rules_are_equivalent(self):
        self.run_setup("--apply", "fonts", "--size", "12", "--rgba", "rgb", answer="y\n")
        file = self.config / "fontconfig/conf.d/60-cachyos-fonts.conf"
        tree = ET.fromstring(file.read_text())
        for name, tag, value in (("hinting", "bool", "true"), ("hintstyle", "const", "hintslight"),
                                 ("antialias", "bool", "true")):
            rule = ET.SubElement(tree, "match", target="pattern")
            edit = ET.SubElement(rule, "edit", mode="assign", name=name)
            ET.SubElement(edit, tag).text = value
        for node in tree.iter():
            node.attrib = dict(reversed(list(node.attrib.items())))
        tree.insert(0, ET.Comment("Existing font preferences"))
        ET.indent(tree, space=" ")
        file.write_text(ET.tostring(tree, encoding="unicode"))
        before = file.read_bytes(), file.stat().st_mtime_ns
        self.assertIn("配置就绪（12pt / rgb）", self.run_setup("--status", "fonts").stdout)
        self.run_setup("--apply", "fonts", answer="y\n")
        self.assertEqual((file.read_bytes(), file.stat().st_mtime_ns), before)
        self.assertEqual(len(self.backups()), 1)
        tree.find("./match/edit[@name='antialias']/bool").text = "false"
        file.write_text(ET.tostring(tree, encoding="unicode"))
        self.assertIn("待应用", self.run_setup("--status", "fonts").stdout)

    def test_extra_conflicting_font_rules_are_not_ignored(self):
        self.run_setup("--apply", "fonts", answer="y\n")
        file = self.config / "fontconfig/conf.d/60-cachyos-fonts.conf"
        tree = ET.fromstring(file.read_text())
        rule = ET.SubElement(tree, "match", target="pattern")
        edit = ET.SubElement(rule, "edit", mode="assign", name="hinting")
        ET.SubElement(edit, "bool").text = "false"
        file.write_text(ET.tostring(tree, encoding="unicode"))
        self.assertIn("待应用", self.run_setup("--status", "fonts").stdout)

    def test_kde_and_fonts_share_kdeglobals_without_losing_each_other(self):
        self.run_setup("--apply", "kde", answer="y\n")
        themed = (self.config / "kdeglobals").read_bytes()
        self.run_setup("--apply", "fonts", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "kde").stdout)
        self.run_setup("--restore", answer="y\n")
        self.assertEqual((self.config / "kdeglobals").read_bytes(), themed)


class LoginTest(Fixture):
    def setUp(self):
        super().setUp()
        self.greeter = self.home / "greeter"
        self.greeter.mkdir()
        self.stub("readlink", "echo /usr/lib/systemd/system/plasmalogin.service")
        self.stub("getent", 'printf "plasmalogin:x:%s:%s::%s:/usr/bin/nologin\\n" '
                  f'{os.getuid()} {os.getgid()} "$HOME/greeter"')
        self.stub("sudo", 'exec "$@"')
        self.layout = [
            {"name": "outputs", "data": [{"connectorName": "DP-1", "scale": 1.5}, {"connectorName": "DP-2"}]},
            {"name": "setups", "data": [
                {"outputs": [{"outputIndex": 0, "enabled": True, "priority": 1, "position": {"x": 800, "y": 0}},
                             {"outputIndex": 1, "enabled": True, "priority": 2}]},
                {"outputs": [{"outputIndex": 1, "enabled": True, "priority": 0}]},
            ]},
        ]
        self.source = self.config / "kwinoutputconfig.json"
        self.target = self.greeter / ".config/kwinoutputconfig.json"
        self.write(self.source, json.dumps(self.layout))

    def test_login_preview_cancel_apply_fallback_and_idempotency(self):
        self.run_setup("--preview", "login-screen")
        self.run_setup("--apply", "login-screen", answer="n\n")
        self.assertFalse(self.target.exists())
        result = self.run_setup("--apply", "login-screen", answer="y\n")
        self.assertIn("sudo rm", result.stdout)
        actual = json.loads(self.target.read_text())
        outputs = actual[1]["data"][0]["outputs"]
        self.assertEqual(outputs[0]["position"], {"x": 0, "y": 0})
        self.assertFalse(outputs[1]["enabled"])
        self.assertEqual(actual[1]["data"][1], self.layout[1]["data"][1])
        self.assertEqual(json.loads(self.source.read_text()), self.layout)
        self.assertIn("配置就绪", self.run_setup("--status", "login-screen").stdout)
        before = self.target.stat().st_mtime_ns
        self.run_setup("--apply", "login-screen", answer="y\n")
        self.assertEqual(self.target.stat().st_mtime_ns, before)
        self.assertEqual(len(list(self.target.parent.glob("login-screen-backup.*"))), 1)

    def test_login_ambiguous_primary_invalid_index_and_wrong_manager(self):
        self.layout[1]["data"][1]["outputs"][0]["priority"] = 1
        self.source.write_text(json.dumps(self.layout))
        self.run_setup("--preview", "login-screen", ok=False)
        self.run_setup("--preview", "login-screen", "--primary", "DP-1")
        self.layout[1]["data"][0]["outputs"][0]["outputIndex"] = 90
        self.source.write_text(json.dumps(self.layout))
        self.run_setup("--apply", "login-screen", "--primary", "DP-1", answer="y\n", ok=False)
        self.stub("readlink", "echo /usr/lib/systemd/system/sddm.service")
        self.run_setup("--preview", "login-screen", ok=False)
        self.assertIn("无法检查", self.run_setup("--status", "login-screen").stdout)
        self.assertFalse(self.target.exists())

    def test_login_symlink_target_is_protected(self):
        outside = self.home / "outside.json"
        outside.write_text("keep")
        self.target.parent.mkdir()
        self.target.symlink_to(outside)
        self.run_setup("--apply", "login-screen", answer="y\n", ok=False)
        self.assertEqual(outside.read_text(), "keep")

    def test_login_installs_missing_python_before_generating_layout(self):
        self.missing_commands("python3")
        self.stub("pacman", '''
[[ "$*" == '-Syu --needed python' ]] || exit 97
touch "$HOME/dependencies-installed"
''')
        self.run_setup("--apply", "login-screen", answer="n\n")
        self.assertFalse(self.target.exists())
        self.run_setup("--apply", "login-screen", answer="y\n")
        self.assertIn("配置就绪", self.run_setup("--status", "login-screen").stdout)
