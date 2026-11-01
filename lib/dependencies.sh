#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

dependency_packages() {
    local item tool package
    local -A seen=()
    local -a commands=(flock:util-linux cmp:diffutils awk:gawk grep:grep sed:sed
                       cat:coreutils cp:coreutils mv:coreutils mkdir:coreutils dirname:coreutils
                       mktemp:coreutils chmod:coreutils stat:coreutils install:coreutils date:coreutils rm:coreutils
                       touch:coreutils tr:coreutils)
    case "$MODULE" in
        kde)
            detect_plugins
            if ! { command -v kreadconfig6 >/dev/null && kde_ready; }; then
                commands+=(kreadconfig6:kconfig kwriteconfig6:kconfig qdbus6:qt6-tools
                            plasma-apply-colorscheme:plasma-workspace plasma-apply-desktoptheme:plasma-workspace
                            plasma-apply-cursortheme:plasma-workspace)
                if [[ -z "$PLUGIN_ROOT" ]]; then commands+=(qtpaths6:qt6-base); fi
            fi ;;
        fonts)
            if ! { fonts_available && fonts_ready; }; then
                commands+=(python3:python fc-list:fontconfig fc-cache:fontconfig)
                if [[ ${XDG_CURRENT_DESKTOP:-} == *KDE* ]]; then commands+=(kreadconfig6:kconfig kwriteconfig6:kconfig); fi
            fi ;;
        proton|controller) commands+=(python3:python) ;;
        login-screen) commands+=(sudo:sudo python3:python getent:glibc readlink:coreutils) ;;
        install-mirrors) commands+=(sudo:sudo pgrep:procps-ng) ;;
    esac
    for item in "${commands[@]}"; do
        tool=${item%%:*}; package=${item#*:}
        if ! command -v "$tool" >/dev/null && [[ ! -v seen[$package] ]]; then
            printf '%s\n' "$package"; seen[$package]=1
        fi
    done
    if [[ "$MODULE" == proton || "$MODULE" == controller ]] && [[ ! -f "$DESKTOP_SOURCE" ]]; then printf 'steam\n'; fi
}

run_pacman() {
    need pacman
    if command -v sudo >/dev/null; then sudo pacman "$@"
    elif command -v pkexec >/dev/null; then pkexec pacman "$@"
    else
        need su
        local command
        printf -v command '%q ' pacman "$@"
        su -c "$command"
    fi
}

install_dependencies() {
    (($#)) || return 0
    printf '自动安装缺少的依赖并完整升级系统：%s\n' "$*"
    run_pacman -Syu --needed "$@"
}

preview_dependencies() {
    local -a packages=()
    mapfile -t packages < <(dependency_packages)
    if ((${#packages[@]})); then
        printf '\n确认后自动安装依赖：%s\n包含完整系统升级，保留包管理器确认。\n' "${packages[*]}"
    fi
}

prepare_dependencies() {
    local -a packages=()
    mapfile -t packages < <(dependency_packages)
    install_dependencies "${packages[@]}"
    mapfile -t packages < <(dependency_packages)
    ((${#packages[@]} == 0)) || die "依赖安装后仍不可用：${packages[*]}；未应用配置"
}
