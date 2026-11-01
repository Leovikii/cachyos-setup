#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

heading() {
    if [[ -t 1 && -z ${NO_COLOR+x} && ${TERM:-dumb} != dumb ]]; then printf '\n\033[1;36m  %s\033[0m\n' "$1";
    else printf '\n  %s\n' "$1"; fi
    printf '  ────────────────────────────────────\n'
}

menu_action() {
    local result
    # 不使用 if function/|| function，避免 Bash 在函数内禁用 errexit。
    set +e
    (set -Ee; "$@")
    result=$?
    set -e
    if ((result != 0)); then printf '\n操作失败（%s），请检查以上提示。\n' "$result" >&2; fi
}

category_menu() {
    local title=$1 answer module index status
    shift
    local -a modules=("$@")
    while true; do
        heading "$title"
        for index in "${!modules[@]}"; do
            module=${modules[index]}
            if ! status=$(run_module "$module" status 2>/dev/null); then status='无法检查'; fi
            printf '  %s  %s\n     %s\n' "$((index+1))" "$(module_label "$module")" "$status"
        done
        printf '\n  0  返回\n\n'
        IFS= read -r -p '  选择 › ' answer || return 0
        case "$answer" in
            0) return ;;
            1|2)
                if ((answer <= ${#modules[@]})); then menu_action run_module "${modules[answer-1]}" apply;
                else printf '  无效选择。\n'; fi ;;
            *) printf '  无效选择。\n' ;;
        esac
    done
}

status_menu() {
    local answer
    while true; do
        heading '状态与恢复'
        printf '  1  检查所有配置\n  2  恢复最近的用户配置备份\n\n  登录界面、安装跳过测速：按应用时输出的 sudo 命令恢复。\n  整文件恢复会覆盖备份之后的修改。\n\n  0  返回\n\n'
        IFS= read -r -p '  选择 › ' answer || return 0
        case "$answer" in
            1) menu_action main --status ;;
            2) menu_action restore_latest ;;
            0) return ;;
            *) printf '  无效选择。\n' ;;
        esac
    done
}

main_menu() {
    local answer
    while true; do
        heading "CachyOS Setup  v$APP_VERSION"
        printf '  桌面与游戏环境初始化\n\n  1  桌面美化\n  2  游戏设置\n  3  系统微调\n\n  8  检查更新\n  9  状态与恢复\n  0  退出\n\n'
        IFS= read -r -p '  选择 › ' answer || return 0
        case "$answer" in
            1) category_menu '桌面美化' kde fonts ;;
            2) category_menu '游戏设置' proton controller ;;
            3) category_menu '系统微调' login-screen install-mirrors ;;
            8) menu_action update_repository; return ;;
            9) status_menu ;;
            0) return ;;
            *) printf '  无效选择。\n' ;;
        esac
    done
}
