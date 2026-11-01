#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Proton 和手柄模块共用唯一参数源与运行时入口。
CONFIG_FILE="$CONFIG_HOME/environment.d/90-cachyos-gaming.conf"
DESKTOP_FILE="$DATA_HOME/applications/steam.desktop"
HELPER="$HOME/.local/bin/steam-managed"
ENV_LIBRARY="$DATA_HOME/cachyos-setup/environment.sh"
KDE_FILE="$CONFIG_HOME/plasma-workspace/env/gaming-env.sh"
DESKTOP_SOURCE=/usr/share/applications/steam.desktop
GAMING_TARGETS=("$CONFIG_FILE" "$ENV_LIBRARY" "$HELPER" "$KDE_FILE" "$DESKTOP_FILE")
GAMING_SOURCES=(config library helper kde steam.desktop)
TARGETS=("${GAMING_TARGETS[@]}")
source "$APP_ROOT/assets/steam/environment.sh"
declare -A SETTINGS=()
CONFIG_VALID=true

read_settings() {
    local lines line
    if [[ -e "$CONFIG_FILE" || -L "$CONFIG_FILE" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]] || ! lines=$(steam_config_lines "$CONFIG_FILE"); then CONFIG_VALID=false; return; fi
        while IFS= read -r line; do
            [[ -z "$line" ]] || SETTINGS[${line%%=*}]=${line#*=}
        done <<< "$lines"
    fi
}

has_proton() {
    local key
    for key in $steam_proton_keys; do [[ ! -v SETTINGS[$key] ]] || return 0; done
    return 1
}

print_config() {
    printf '# Managed by cachyos-setup\n# Plain KEY=VALUE only; no shell expressions.\n'
    local key
    for key in $steam_env_keys; do
        if [[ -v SETTINGS[$key] ]]; then printf '%s=%s\n' "$key" "${SETTINGS[$key]}"; fi
    done
}

check_owned() {
    local path=$1
    check_path "$path"
    [[ -e "$path" ]] || return 0
    grep -q '^# Managed by cachyos-setup$' "$path" || die "文件不属于本脚本，未覆盖：$path"
}

check_gaming_paths() {
    local path
    for path in "${TARGETS[@]}"; do check_owned "$path"; done
    [[ "$CONFIG_VALID" == true ]] || die '游戏参数配置无效，请先修正后重试'
}

render_desktop() {
    python3 - "$DESKTOP_SOURCE" "$HELPER" <<'PY_DESKTOP'
import sys
from pathlib import Path
p=sys.argv[2].replace('\\','\\\\\\\\').replace('"','\\\\\\"').replace('$','\\\\$').replace('`','\\\\`').replace('%','%%')
if '\n' in p or '\r' in p: sys.exit('启动器路径不能含换行')
print('# Managed by cachyos-setup')
count=0
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith('Exec='):
        command=line[5:]
        if not (command=='/usr/bin/steam' or command.startswith('/usr/bin/steam ')):
            sys.exit('系统 Steam 入口的 Exec 格式未知，未安装')
        line='Exec="'+p+'"'+command[len('/usr/bin/steam'):]
        count+=1
    print(line)
if not count: sys.exit('Steam 入口缺少 Exec，未安装')
PY_DESKTOP
}

render_kde() {
    cat <<'KDE'
# Managed by cachyos-setup
if [ -r "${XDG_DATA_HOME:-$HOME/.local/share}/cachyos-setup/environment.sh" ]; then
    . "${XDG_DATA_HOME:-$HOME/.local/share}/cachyos-setup/environment.sh"
    steam_load_environment || printf '游戏会话参数未加载，请检查 90-cachyos-gaming.conf。\n' >&2
fi
KDE
}

integration_ready() {
    [[ -r "$CONFIG_FILE" && -x "$HELPER" && -r "$ENV_LIBRARY" && -r "$KDE_FILE" && -r "$DESKTOP_FILE" && -f "$DESKTOP_SOURCE" ]] || return 1
    cmp -s "$HELPER" "$APP_ROOT/assets/steam/steam-managed" &&
        cmp -s "$ENV_LIBRARY" "$APP_ROOT/assets/steam/environment.sh" &&
        cmp -s "$KDE_FILE" <(render_kde) && cmp -s "$DESKTOP_FILE" <(render_desktop)
}

proton_complete() {
    local key
    for key in PROTON_ENABLE_WAYLAND PROTON_DXVK_LOWLATENCY DXVK_FRAME_PACE DXVK_FRAME_RATE VKD3D_FRAME_RATE MESA_SHADER_CACHE_MAX_SIZE; do
        [[ -v SETTINGS[$key] ]] || return 1
    done
}

refresh_menu() {
    if command -v kbuildsycoca6 >/dev/null && [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]]; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || printf '菜单刷新未成功；重新登录后会刷新。\n' >&2
    fi
}

refresh_user_environment() {
    # A running desktop cannot be rewritten; managed launches read the file directly.
    if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* && -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v systemctl >/dev/null; then
        local -a keys=() values=()
        if has_proton; then read -r -a keys <<< "$steam_proton_keys $steam_legacy_keys"; fi
        if [[ -v SETTINGS[SDL_GAMECONTROLLERTYPE] ]]; then keys+=(SDL_GAMECONTROLLERTYPE); fi
        if ! systemctl --user unset-environment "${keys[@]}"; then
            printf '用户服务环境未刷新；下次登录生效。\n' >&2
            return
        fi
        if [[ -f "$CONFIG_FILE" ]]; then
            local validated
            validated=$(steam_config_lines "$CONFIG_FILE") || return 1
            if [[ -n "$validated" ]]; then mapfile -t values <<< "$validated"; fi
            if ((${#values[@]})); then
                systemctl --user set-environment "${values[@]}" || printf '用户服务环境未刷新；下次登录生效。\n' >&2
                if command -v dbus-update-activation-environment >/dev/null; then
                    dbus-update-activation-environment "${values[@]}" || printf 'D-Bus 启动环境未刷新；下次登录生效。\n' >&2
                fi
            fi
        fi
    fi
}

preview_gaming() {
    check_gaming_paths
    steam_config_lines <(print_config) >/dev/null || die '游戏参数不合法'
    if [[ -f "$DESKTOP_SOURCE" ]] && command -v python3 >/dev/null; then render_desktop >/dev/null; fi
    if [[ ! -f "$DESKTOP_SOURCE" ]]; then printf '确认后自动安装原生 Steam（Flatpak 版不提供此入口）。\n'; fi
    printf '范围：当前用户会话全局，供 Steam 及其它继承环境的程序读取。\n'
    printf '配置参数：\n'; print_config
    printf '\n将创建或更新以下文件，应用前备份：\n'; show_targets
    printf '不会修改游戏启动选项、账户、存档或 Steam Input 布局。\n'
    printf '请完全退出后重启 Steam；完整更新桌面会话需要注销重登。\n'
}

stage_gaming() {
    need python3
    local stage
    stage=$(mktemp -d)
    GAMING_STAGE=$stage
    trap 'rm -rf -- "${GAMING_STAGE:-}"' EXIT
    print_config > "$stage/config"
    steam_config_lines "$stage/config" >/dev/null || die '配置校验失败'
    render_desktop > "$stage/steam.desktop"
    render_kde > "$stage/kde"
    cp -- "$APP_ROOT/assets/steam/environment.sh" "$stage/library"
    cp -- "$APP_ROOT/assets/steam/steam-managed" "$stage/helper"
    if command -v desktop-file-validate >/dev/null; then desktop-file-validate "$stage/steam.desktop"; fi
}

install_gaming_stage() {
    local path index=0
    for path in "${GAMING_TARGETS[@]}"; do
        if [[ "$path" == "$HELPER" ]]; then atomic_install "$GAMING_STAGE/${GAMING_SOURCES[index]}" "$path" 755;
        else atomic_install "$GAMING_STAGE/${GAMING_SOURCES[index]}" "$path"; fi
        index=$((index+1))
    done
}

apply_gaming() {
    check_gaming_paths
    [[ -f "$DESKTOP_SOURCE" ]] || die "安装后仍找不到原生 Steam 入口：$DESKTOP_SOURCE"
    stage_gaming
    local path index=0 changed=false
    for path in "${GAMING_TARGETS[@]}"; do
        if [[ ! -f "$path" ]] || ! cmp -s "$path" "$GAMING_STAGE/${GAMING_SOURCES[index]}"; then changed=true; fi
        index=$((index+1))
    done
    [[ -x "$HELPER" ]] || changed=true
    if ! "$changed"; then printf '配置已符合目标，跳过写入和备份。\n'; return; fi
    backup_files
    install_gaming_stage
    integration_ready || die 'Steam 入口校验失败，可恢复最近备份'
    refresh_user_environment
    refresh_menu
    printf '配置已保存。请完全退出并重新启动 Steam；注销重登后全局环境完整生效。\n'
}
