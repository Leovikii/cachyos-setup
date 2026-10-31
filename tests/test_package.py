"""Check the committed source archive and its executable entry point."""
import hashlib
import shutil
import subprocess
import tarfile

from test_setup import Fixture, ROOT


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

    def test_package_contains_runtime_license_and_valid_checksum(self):
        self.commit()
        output = self.base / "package"
        result = subprocess.run(["bash", str(self.repo / "scripts/package.sh"), str(output)],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        archive = output / "cachyos-setup-0.1.0.tar.gz"
        self.assertEqual((output / "SHA256SUMS").read_text().split()[0], hashlib.sha256(archive.read_bytes()).hexdigest())
        with tarfile.open(archive) as bundle:
            names = bundle.getnames()
            self.assertIn("cachyos-setup-0.1.0/assets/kde/LICENSE.catppuccin", names)
            self.assertIn("cachyos-setup-0.1.0/lib/fontconfig.py", names)
            self.assertNotIn("cachyos-setup-0.1.0/scripts/check.sh", names)

    def test_package_rejects_invalid_committed_version(self):
        (self.repo / "VERSION").write_text("invalid\n")
        self.commit()
        result = subprocess.run(["bash", str(self.repo / "scripts/package.sh"), str(self.base / "package")],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.base / "package").exists())
