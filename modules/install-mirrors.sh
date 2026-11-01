#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
INSTALL_ETC=/etc
INSTALL_LIVE=/run/archiso/bootmnt
INSTALL_PACMAN_LOCK=/var/lib/pacman/db.lck

install_paths() {
    INSTALL_SCRIPT=$INSTALL_ETC/calamares/scripts/update-mirrorlist
    TARGETS=("$INSTALL_ETC/pacman.d/mirrorlist" "$INSTALL_ETC/pacman.d/cachyos-mirrorlist"
             "$INSTALL_ETC/pacman.d/cachyos-v3-mirrorlist" "$INSTALL_ETC/pacman.d/cachyos-v4-mirrorlist"
             "$INSTALL_SCRIPT")
}
install_paths

feature_options() { (($# == 0)) || die '安装跳过测速不接受额外参数'; }

install_live() {
    [[ -d "$INSTALL_LIVE" ]] && grep -Eq '^ID=(cachyos|"cachyos")$' "$INSTALL_ETC/os-release"
}

install_content() {
    case "$1" in
        0) printf '%s\n' 'Server = https://archlinux.cachyos.org/repo/$repo/os/$arch' ;;
        1) printf '%s\n' 'Server = https://cdn77.cachyos.org/repo/$arch/$repo' ;;
        2) printf '%s\n' 'Server = https://cdn77.cachyos.org/repo/$arch_v3/$repo' ;;
        3) printf '%s\n' 'Server = https://cdn77.cachyos.org/repo/$arch_v4/$repo' ;;
        4) printf '%s\n' '#!/usr/bin/env bash' '# Managed by cachyos-setup: install-mirrors' \
               'printf "Skipping mirror ranking; using configured CDN mirrors.\n"' 'exit 0' ;;
        *) die '无效的安装镜像目标' ;;
    esac
}

install_validate() {
    install_live || die '仅支持 CachyOS Live ISO；请在安装环境中运行'
    local target original
    for target in "${TARGETS[@]}"; do
        check_path "$target"
        [[ -f "$target" && -r "$target" ]] || die "缺少或无法读取安装文件：$target；请先从欢迎界面启动安装器"
    done
    if ! cmp -s -- <(install_content 4) "$INSTALL_SCRIPT"; then
        original=$(awk '{gsub(/^[ \t]+|[ \t\r]+$/, "")} NF && $0 !~ /^#/' "$INSTALL_SCRIPT")
        [[ "$original" == $'echo "Updating rate-mirrors"\nsudo pacman -Sy --noconfirm --needed cachyos-rate-mirrors rate-mirrors\nsudo cachyos-rate-mirrors' ]] ||
            die '无法识别安装器测速脚本，未修改；请核对当前 ISO 的安装流程'
    fi
}

install_preflight() {
    need pgrep
    pgrep -x calamares >/dev/null || die '请先从欢迎界面打开安装器，停留在配置页面后再应用'
    [[ ! -e "$INSTALL_PACMAN_LOCK" ]] || die 'pacman 正在操作或存在锁文件，请等待并核对安装状态；不要在安装过程中应用'
}

install_ready() {
    local index
    for index in "${!TARGETS[@]}"; do
        cmp -s -- <(install_content "$index") "${TARGETS[index]}" || return 1
    done
}

feature_status() {
    if ! install_live 2>/dev/null; then printf '不适用（仅限 CachyOS Live ISO）\n'; return; fi
    if ! (install_validate) 2>/dev/null; then printf '无法检查（安装文件缺失、不可读或结构不支持）\n'; return; fi
    if install_ready; then printf '配置就绪（安装跳过测速，使用官方 CDN）\n'
    elif cmp -s -- <(install_content 4) "$INSTALL_SCRIPT"; then printf '配置不完整（测速已跳过，镜像列表有变化）\n'
    else printf '未配置\n'; fi
}

feature_preview() {
    install_validate
    install_preflight
    printf '\n安装跳过测速\n'
    printf '范围：当前 Live ISO 的 Calamares 安装流程；请停留在安装器配置页面，不要开始安装。\n'
    printf '跳过 update-mirrorlist 测速；四份镜像列表仅保留以下官方 CDN：\n'
    printf '  CachyOS：cdn77.cachyos.org（全球 CDN，保留普通/v3/v4 架构变量）\n'
    printf '  Arch：archlinux.cachyos.org\n'
    printf '将通过内部 sudo 修改以下文件：\n'; show_targets
    printf '应用前备份全部文件并输出 sudo 恢复命令；整文件恢复会覆盖后续修改。\n'
    printf '不安装软件、不测速、不联网探测；CDN 不可达时需恢复或手动换源。\n'
    printf '应用后直接继续当前安装器；重新从欢迎界面启动会覆盖测速脚本，需再次应用。\n'
    printf '镜像列表会随安装流程复制到目标系统；不修改安装后系统的测速定时器。\n'
    printf 'Live ISO 重启后本次修改及备份会丢失。\n'
    if install_ready; then printf '当前配置已符合预设，执行时将跳过。\n'; fi
}

install_root_apply() (
    install_validate
    install_preflight
    if install_ready; then printf '配置已符合目标，跳过写入和备份。\n'; return; fi
    local backup index target mode
    local -a pending=()
    backup=$(mktemp -d "$INSTALL_ETC/pacman.d/cachyos-setup-install-backup.XXXXXXXX")
    printf '备份：%s\n' "$backup"
    for index in "${!TARGETS[@]}"; do cp -a -- "${TARGETS[index]}" "$backup/$index"; done
    printf '恢复命令（整文件恢复；请先停止安装）：\n'
    for index in "${!TARGETS[@]}"; do printf 'sudo cp -a -- %q %q\n' "$backup/$index" "${TARGETS[index]}"; done
    trap 'rm -f -- "${pending[@]}"' EXIT
    # 先生成全部文件，镜像列表写入成功后才替换测速入口。
    for index in "${!TARGETS[@]}"; do
        target=${TARGETS[index]}
        pending[index]=$(mktemp "$(dirname -- "$target")/.cachyos-setup-XXXXXXXX")
        install_content "$index" > "${pending[index]}"
        mode=644; [[ "$target" != "$INSTALL_SCRIPT" ]] || mode=755
        chmod "$mode" -- "${pending[index]}"
    done
    install_validate
    install_preflight
    for index in "${!TARGETS[@]}"; do mv -fT -- "${pending[index]}" "${TARGETS[index]}"; done
    install_ready || die "写入校验失败，请按以上命令恢复备份：$backup"
    printf '已应用安装跳过测速。请直接继续当前安装器，不要重新从欢迎界面启动。\n'
)

feature_apply() {
    need sudo
    # 只传递本模块需要的函数和固定路径；提权后重新检查，不加载用户配置。
    {
        printf 'set -Eeuo pipefail\n'
        declare -f die need check_path install_paths install_live install_content install_validate install_preflight install_ready install_root_apply
        cat <<'ROOT'
INSTALL_ETC=$1 INSTALL_LIVE=$2 INSTALL_PACMAN_LOCK=$3
install_paths
install_root_apply
ROOT
    } | sudo bash -s -- "$INSTALL_ETC" "$INSTALL_LIVE" "$INSTALL_PACMAN_LOCK"
}
