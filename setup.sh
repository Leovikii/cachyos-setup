#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -Eeuo pipefail
APP_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
APP_VERSION=$(< "$APP_ROOT/VERSION")
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'VERSION 格式无效\n' >&2; exit 1; }
source "$APP_ROOT/lib/common.sh"
source "$APP_ROOT/lib/dependencies.sh"
source "$APP_ROOT/lib/menu.sh"
source "$APP_ROOT/lib/update.sh"

valid_module() { case "$1" in kde|fonts|proton|controller|login-screen|install-mirrors) return 0 ;; *) return 1 ;; esac; }
module_label() {
    case "$1" in
        kde) printf 'KDE 外观' ;; fonts) printf '字体设置' ;; proton) printf 'Proton 全局预设' ;;
        controller) printf '黑武士 5 Pro → Xbox 360' ;; login-screen) printf '登录界面仅显示主屏' ;;
        install-mirrors) printf '安装跳过测速' ;;
    esac
}

run_module() (
    set -Eeuo pipefail
    trap 'printf "操作未完成。已创建的备份会保留，可从“状态与恢复”查看恢复方式。\n" >&2' ERR
    MODULE=$1
    local_action=$2
    shift 2
    source "$APP_ROOT/modules/$MODULE.sh"
    if [[ "$local_action" == applicable ]]; then
        if declare -F feature_applicable >/dev/null; then feature_applicable; else return 0; fi
        exit $?
    fi
    feature_options "$@"
    case "$local_action" in
        status) feature_status ;;
        preview) preview_dependencies; feature_preview ;;
        apply|apply-confirmed)
            ((EUID != 0)) || die '请以桌面普通用户运行，不要 sudo 整个脚本'
            preview_dependencies
            feature_preview
            if [[ "$local_action" == apply ]] && ! confirm; then printf '已取消。\n'; exit 0; fi
            prepare_dependencies
            # 新工具可读取已有设置；保留显式传入的选项，并重新校验现场。
            feature_options "$@"
            feature_preview >/dev/null
            lock_operation
            feature_apply
            ;;
    esac
)

apply_all() {
    ((EUID != 0)) || die '请以桌面普通用户运行，不要 sudo 整个脚本'
    local module
    local -a selected=()
    for module in "$@"; do
        if run_module "$module" applicable; then selected+=("$module");
        else printf '跳过不适用项：%s\n' "$(module_label "$module")"; fi
    done
    ((${#selected[@]})) || { printf '当前环境没有适用项。\n'; return; }
    for module in "${selected[@]}"; do run_module "$module" preview; done
    printf '\n安装全部：%s 项；按顺序自动补齐依赖并应用。每项独立备份，失败即停止，已完成项保留。\n' "${#selected[@]}"
    if ! confirm '确认安装全部？'; then printf '已取消。\n'; return; fi
    for module in "${selected[@]}"; do run_module "$module" apply-confirmed; done
}

usage() {
    cat <<'EOF'
用法：bash cachyos-setup.sh [操作]（源码仓库使用 bash setup.sh）
  无参数                  打开菜单
  --status [模块]         只读检查配置
  --preview 模块 [选项]   预览修改，不写入
  --apply 模块 [选项]     预览并确认后应用
  --apply-all 分类        确认后安装分类下全部适用功能
  --restore               预览并确认后恢复最近的用户配置备份
  --update                检查脚本更新，确认后更新代码
  --version / --help
模块：kde fonts proton controller login-screen install-mirrors
分类：desktop gaming system（桌面美化 / 游戏设置 / 系统微调）
字体选项：--size 9..18 --rgba none|rgb|bgr|vrgb|vbgr
Proton 选项：--fps N --cache-size 12G --anti-lag-layer --no-anti-lag-layer
             --dx12-lowlatency --no-dx12-lowlatency --fsr-indicator --no-fsr-indicator
登录单屏选项：--primary DP-1
安装跳过测速：仅限 Live ISO；先从欢迎界面打开安装器，停留在配置页面后应用。
所有应用操作均需交互确认，不支持无人值守跳过确认。
EOF
}

main() {
    local action=${1:-} module
    case "$action" in
        '') main_menu ;;
        --version) (($# == 1)) || die '多余参数'; printf '%s\n' "$APP_VERSION" ;;
        --help|-h) (($# == 1)) || die '多余参数'; usage ;;
        --status)
            (($# <= 2)) || die '状态检查只接受一个模块'
            if (($# == 2)); then valid_module "$2" || die '未知模块'; run_module "$2" status;
            else for module in kde fonts proton controller login-screen install-mirrors; do printf '%s：' "$(module_label "$module")"; run_module "$module" status; done; fi ;;
        --preview|--apply)
            (($# >= 2)) || die '缺少模块，请使用 --help'
            module=$2; valid_module "$module" || die "未知模块：$module"
            shift 2; run_module "$module" "${action#--}" "$@" ;;
        --apply-all)
            (($# == 2)) || die '安装全部需要且只接受一个分类'
            case "$2" in
                desktop) apply_all kde fonts ;;
                gaming) apply_all proton controller ;;
                system) apply_all login-screen install-mirrors ;;
                *) die "未知分类：$2" ;;
            esac ;;
        --restore) (($# == 1)) || die '多余参数'; (restore_latest) ;;
        --update) (($# == 1)) || die '多余参数'; update_repository ;;
        *) die "未知操作：$action，请使用 --help" ;;
    esac
}
main "$@"
