#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
output=${1:?需要指定输出目录}
revision=${2:-HEAD}
version=$(git show "$revision:VERSION")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf '版本号无效\n' >&2; exit 1; }
name="cachyos-setup-$version"
mkdir -p -- "$output"
output=$(cd -- "$output" && pwd)
git archive --format=tar --prefix="$name/" "$revision" | gzip -n > "$output/$name.tar.gz"
(cd -- "$output" && sha256sum "$name.tar.gz" > SHA256SUMS)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
tar -xzf "$output/$name.tar.gz" -C "$temporary"
for path in LICENSE README.md setup.sh lib/common.sh lib/menu.sh lib/update.sh lib/fontconfig.py modules/kde.sh modules/fonts.sh modules/proton.sh modules/controller.sh modules/gaming.sh modules/login-screen.sh assets/kde/LICENSE.catppuccin assets/kde/CatppuccinMochaPink.colors assets/steam/environment.sh assets/steam/steam-managed; do
    [[ -f "$temporary/$name/$path" ]] || { printf '脚本包缺少 %s\n' "$path" >&2; exit 1; }
done
[[ $(bash "$temporary/$name/setup.sh" --version) == "$version" ]]
bash "$temporary/$name/setup.sh" --help >/dev/null
printf '脚本包已构建并校验：%s/%s.tar.gz\n' "$output" "$name"
