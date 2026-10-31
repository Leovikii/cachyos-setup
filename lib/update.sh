#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

download_release_file() {
    local url="https://github.com/Leovikii/cachyos-setup/releases/latest/download/$1"
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error --connect-timeout 15 --max-time 120 "$url" -o "$2"
    else
        need wget
        wget --timeout=30 --tries=2 -q "$url" -O "$2"
    fi
}

update_release() (
    ((EUID != 0)) || die '请以桌面普通用户运行'
    need sha256sum
    local target=$CACHYOS_SETUP_SCRIPT temporary expected actual version original
    check_path "$target"
    [[ -f "$target" && -w "$target" ]] || die '当前脚本不可写，请重新下载最新版'
    original=$(sha256sum -- "$target")
    temporary=$(mktemp -d)
    trap 'rm -rf -- "$temporary"' EXIT
    printf '正在检查最新发行版…\n'
    download_release_file cachyos-setup.sh "$temporary/cachyos-setup.sh"
    download_release_file SHA256SUMS "$temporary/SHA256SUMS"
    expected=$(awk '$2=="cachyos-setup.sh" {print $1}' "$temporary/SHA256SUMS")
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die '发行版校验文件无效'
    actual=$(sha256sum -- "$temporary/cachyos-setup.sh")
    [[ ${actual%% *} == "$expected" ]] || die '发行版 SHA-256 校验失败，未更新'
    bash -n "$temporary/cachyos-setup.sh"
    version=$(bash "$temporary/cachyos-setup.sh" --version)
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die '发行版版本号无效'
    if cmp -s -- "$temporary/cachyos-setup.sh" "$target"; then
        printf '当前已是最新发行版（v%s）。\n' "$APP_VERSION"; return
    fi
    printf '\n当前 v%s → 最新 v%s\n将替换：%s\n仅更新脚本，不应用系统配置。\n' "$APP_VERSION" "$version" "$target"
    if ! confirm '确认更新？'; then printf '已取消更新。\n'; return; fi
    check_path "$target"
    [[ $(sha256sum -- "$target") == "$original" ]] || die '脚本在检查后发生变化，未更新'
    atomic_install "$temporary/cachyos-setup.sh" "$target" "$(stat -c %a -- "$target")"
    printf '已更新至 v%s。请重新运行 bash %q。\n' "$version" "$target"
)

update_repository() {
    if [[ -n ${CACHYOS_SETUP_SCRIPT:-} ]]; then update_release; return; fi
    need git
    local top branch upstream remote current candidate version path
    top=$(git -C "$APP_ROOT" rev-parse --show-toplevel 2>/dev/null) || die '源码副本需要通过 Git 克隆更新；也可下载发行版单文件脚本'
    [[ "$top" == "$APP_ROOT" ]] || die '脚本不在 Git 仓库根目录'
    remote=$(git -C "$APP_ROOT" config --get remote.origin.url) || die '缺少 origin'
    case "$remote" in
        https://github.com/Leovikii/cachyos-setup.git|https://github.com/Leovikii/cachyos-setup|git@github.com:Leovikii/cachyos-setup.git) ;;
        *) die 'origin 不是 Leovikii/cachyos-setup，未自动更新' ;;
    esac
    [[ -z $(git -C "$APP_ROOT" status --porcelain) ]] || die '工作区有本地修改或未跟踪文件，请先自行处理'
    branch=$(git -C "$APP_ROOT" symbolic-ref --short -q HEAD) || die '当前为 detached HEAD，请切回跟踪 origin 的分支'
    upstream=$(git -C "$APP_ROOT" rev-parse --symbolic-full-name '@{upstream}' 2>/dev/null) || die '当前分支没有上游'
    [[ "$upstream" == "refs/remotes/origin/$branch" ]] || die '仅支持当前分支跟踪同名 origin 分支'
    current=$(git -C "$APP_ROOT" rev-parse HEAD)
    printf '正在检查 origin/%s…\n' "$branch"
    git -C "$APP_ROOT" fetch --no-tags origin "$branch"
    candidate=$(git -C "$APP_ROOT" rev-parse FETCH_HEAD)
    if [[ "$current" == "$candidate" ]]; then printf '当前已是最新提交（v%s）。\n' "$APP_VERSION"; return; fi
    git -C "$APP_ROOT" merge-base --is-ancestor "$current" "$candidate" || die '本地提交领先或分支已分叉，未更新，请手动处理'
    version=$(git -C "$APP_ROOT" show "$candidate:VERSION")
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die '远端 VERSION 格式无效'
    for path in setup.sh lib/common.sh lib/menu.sh lib/update.sh lib/fontconfig.py modules/kde.sh modules/fonts.sh modules/gaming.sh modules/proton.sh modules/controller.sh modules/login-screen.sh assets/steam/environment.sh assets/steam/steam-managed assets/kde/CatppuccinMochaPink.colors; do
        [[ $(git -C "$APP_ROOT" cat-file -t "$candidate:$path") == blob ]] || die "远端缺少必要文件：$path"
    done
    printf '\n当前 v%s → 远端 v%s（%s）\n' "$APP_VERSION" "$version" "${candidate:0:8}"
    git -C "$APP_ROOT" --no-pager log --oneline --max-count=8 "$current..$candidate"
    printf '仅更新仓库代码，不安装软件、不应用系统配置；完成后请重新运行脚本。\n'
    if ! confirm '确认更新？'; then printf '已取消更新。\n'; return; fi
    [[ $(git -C "$APP_ROOT" rev-parse HEAD) == "$current" && -z $(git -C "$APP_ROOT" status --porcelain) ]] || die '仓库在检查后发生变化，未更新'
    git -C "$APP_ROOT" merge --ff-only "$candidate"
    printf '已更新至 v%s。请重新运行 bash setup.sh。\n' "$version"
}
