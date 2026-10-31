#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
output=${1:?需要指定输出目录}
revision=${2:-HEAD}
version=$(git show "$revision:VERSION")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf '版本号无效\n' >&2; exit 1; }
mkdir -p -- "$output"
output=$(cd -- "$output" && pwd)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
git archive "$revision" | tar -x -C "$temporary"
for path in VERSION LICENSE setup.sh lib/common.sh lib/menu.sh lib/update.sh lib/fontconfig.py modules/kde.sh modules/fonts.sh modules/proton.sh modules/controller.sh modules/gaming.sh modules/login-screen.sh assets/kde/LICENSE.catppuccin assets/kde/CatppuccinMochaPink.colors assets/steam/environment.sh assets/steam/steam-managed; do
    [[ -f "$temporary/$path" ]] || { printf '缺少运行文件：%s\n' "$path" >&2; exit 1; }
done
python3 - "$temporary" "$output/cachyos-setup.sh" <<'PY'
import hashlib
from pathlib import Path
import shlex
import sys

root, output = map(Path, sys.argv[1:])
files = [root / name for name in ('VERSION', 'LICENSE', 'setup.sh')]
for directory in ('lib', 'modules', 'assets'):
    files.extend(sorted(path for path in (root / directory).rglob('*') if path.is_file()))
with output.open('w') as script:
    script.write('''#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Built by GitHub Actions from committed source; includes all runtime files and licenses.
set -Eeuo pipefail
bundle_script=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")
bundle_root=$(mktemp -d)
trap 'rm -rf -- "$bundle_root"' EXIT
''')
    for path in files:
        relative = path.relative_to(root)
        content = path.read_text()
        delimiter = 'CACHYOS_EMBED_' + hashlib.sha256(content.encode()).hexdigest()
        assert delimiter not in content.splitlines()
        script.write(f'mkdir -p -- "$bundle_root"/{shlex.quote(str(relative.parent))}\n')
        script.write(f'cat > "$bundle_root"/{shlex.quote(str(relative))} <<\'{delimiter}\'\n')
        script.write(content)
        if not content.endswith('\n'):
            script.write('\n')
        script.write(delimiter + '\n')
    script.write('CACHYOS_SETUP_SCRIPT="$bundle_script" bash "$bundle_root/setup.sh" "$@"\n')
output.chmod(0o755)
PY
bash -n "$output/cachyos-setup.sh"
[[ $(bash "$output/cachyos-setup.sh" --version) == "$version" ]]
bash "$output/cachyos-setup.sh" --help >/dev/null
(cd -- "$output" && sha256sum cachyos-setup.sh > SHA256SUMS)
printf '单文件脚本已构建并校验：%s/cachyos-setup.sh\n' "$output"
