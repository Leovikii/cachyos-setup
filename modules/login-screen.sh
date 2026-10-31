#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
PRIMARY=''
TARGETS=()

feature_options() {
    while (($#)); do
        case "$1" in
            --primary)
                (($# >= 2)) && [[ -n "$2" && "$2" != --* ]] || die '--primary 后需要接口名，例如 DP-1'
                PRIMARY=$2; shift 2 ;;
            *) die "未知登录屏幕选项：$1" ;;
        esac
    done
}

login_paths() {
    need python3
    local manager account
    manager=$(readlink -f /etc/systemd/system/display-manager.service) || die '未找到登录管理器服务'
    [[ "${manager##*/}" == plasmalogin.service ]] || die '仅支持 Plasma Login Manager，不支持 SDDM/X11'
    account=$(getent passwd plasmalogin) || die '缺少 plasmalogin 账户'
    IFS=: read -r _ _ LOGIN_UID LOGIN_GID _ LOGIN_HOME _ <<< "$account"
    [[ "$LOGIN_UID" =~ ^[0-9]+$ && "$LOGIN_GID" =~ ^[0-9]+$ && "$LOGIN_HOME" == /* && "$LOGIN_HOME" != / && "$LOGIN_HOME" != *$'\n'* ]] || die '登录账户信息无效'
    LOGIN_SOURCE="$CONFIG_HOME/kwinoutputconfig.json"
    LOGIN_TARGET="$LOGIN_HOME/.config/kwinoutputconfig.json"
    [[ -f "$LOGIN_SOURCE" ]] || die "找不到 $LOGIN_SOURCE；请先在 KDE 显示设置中保存布局"
}

login_generate() {
    python3 - "$LOGIN_SOURCE" "$PRIMARY" <<'PY_LOGIN'
import json
import sys

try:
    with open(sys.argv[1], encoding='utf-8') as stream:
        config = json.load(stream)
    if not isinstance(config, list):
        raise ValueError('不支持的 KWin 配置格式')
    groups = {group['name']: group['data'] for group in config}
    if len(groups) != len(config):
        raise ValueError('配置包含重复分组')
    outputs, setups = groups['outputs'], groups['setups']
    if not isinstance(outputs, list) or not outputs or not isinstance(setups, list) or not setups:
        raise ValueError('配置没有显示器或布局')
    names = [output['connectorName'] for output in outputs]
    candidates = set()
    for setup in setups:
        if not setup['outputs']:
            raise ValueError('发现空布局')
        indices = set()
        for output in setup['outputs']:
            index = output['outputIndex']
            if type(index) is not int or not 0 <= index < len(outputs) or index in indices:
                raise ValueError('显示器索引无效或重复')
            indices.add(index)
            if type(output['enabled']) is not bool:
                raise ValueError('显示器 enabled 字段无效')
            if output['enabled'] and output.get('priority') == 1:
                candidates.add(names[index])
    primary = sys.argv[2]
    if not primary:
        if len(candidates) != 1:
            raise ValueError('无法唯一推断主屏，请用 --primary 指定；可用接口：' + ', '.join(names))
        primary = candidates.pop()
    matching = {index for index, name in enumerate(names) if name == primary}
    if not matching:
        raise ValueError('主屏不存在；可用接口：' + ', '.join(names))
    changed = 0
    for setup in setups:
        active = [output for output in setup['outputs'] if output['outputIndex'] in matching]
        if not active:
            # 主屏未连接时保留原布局，避免只连副屏时无法登录。
            continue
        if len(active) != 1:
            raise ValueError('同一布局中主屏接口不唯一')
        for output in setup['outputs']:
            enabled = output is active[0]
            output.update(enabled=enabled, priority=1 if enabled else 0, replicationSource='')
            if enabled:
                output['position'] = {'x': 0, 'y': 0}
        changed += 1
    if not changed:
        raise ValueError('没有包含该主屏的布局')
    print(f'登录主屏：{primary}；生成 {changed} 个单屏布局，主屏缺席的布局保留。', file=sys.stderr)
    json.dump(config, sys.stdout, ensure_ascii=False, indent=4, allow_nan=False)
    print()
except (OSError, ValueError, KeyError, TypeError) as error:
    sys.exit(f'错误：无法生成配置：{error}')
PY_LOGIN
}

feature_status() {
    local generated
    # 子 Shell 隔离检测错误，不为状态检查提权。
    if ! generated=$( { login_paths; login_generate; } 2>/dev/null); then printf '无法检查（登录管理器或显示布局不适用）\n'; return; fi
    login_paths
    if [[ ! -r "$LOGIN_TARGET" ]]; then printf '无法检查（登录账户配置不可读；应用时会提权核对）\n'; return; fi
    if printf '%s\n' "$generated" | python3 -c 'import json,sys; sys.exit(json.load(sys.stdin)!=json.load(open(sys.argv[1])))' "$LOGIN_TARGET" 2>/dev/null; then
        printf '配置就绪（下次显示登录界面时验证）\n'
    else printf '待应用\n'; fi
}

feature_preview() {
    login_paths
    GENERATED=$(login_generate)
    printf '\n登录界面仅显示主屏\n'
    printf '读取：%s\n写入：%s（内部 sudo）\n' "$LOGIN_SOURCE" "$LOGIN_TARGET"
    printf '将主屏移到 (0,0)，关闭同一布局的其它屏幕；主屏缺席的历史布局保留。\n'
    printf '保留当前桌面配置、分辨率和缩放；不管理锁屏、不重启登录服务。\n'
    printf '在登录账户配置目录备份，并输出手动恢复命令；下次显示登录界面时验证。\n'
}

feature_apply() {
    need sudo
    local generated
    generated=$(mktemp)
    trap 'rm -f -- "${LOGIN_TEMP:-}"' EXIT
    LOGIN_TEMP=$generated
    printf '%s\n' "$GENERATED" > "$generated"
    sudo bash -s -- "$LOGIN_HOME" "$LOGIN_UID" "$LOGIN_GID" "$generated" <<'ROOT'
set -euo pipefail
home=$1 uid=$2 gid=$3 generated=$4
config=$home/.config
target=$config/kwinoutputconfig.json
path=$target
while [[ "$path" != / ]]; do
    [[ ! -L "$path" ]] || { printf '拒绝写入符号链接：%s\n' "$path" >&2; exit 1; }
    path=$(dirname -- "$path")
done
[[ -d "$home" && ( ! -e "$config" || -d "$config" ) && ( ! -e "$target" || -f "$target" ) ]] || exit 1
if [[ -f "$target" ]] && cmp -s -- "$generated" "$target"; then
    printf '登录显示配置已符合，无需更改。\n'
    exit 0
fi
if [[ ! -d "$config" ]]; then install -d -o "$uid" -g "$gid" -m 700 -- "$config"; fi
backup=$(mktemp -d "$config/login-screen-backup.XXXXXXXX")
if [[ -f "$target" ]]; then cp -a -- "$target" "$backup/kwinoutputconfig.json";
else touch "$backup/original-absent"; fi
printf '备份：%s\n恢复命令（整文件恢复）：\n' "$backup"
if [[ -f "$backup/original-absent" ]]; then printf 'sudo rm -- %q\n' "$target";
else printf 'sudo cp -a -- %q %q\n' "$backup/kwinoutputconfig.json" "$target"; fi
pending=$(mktemp "$config/.kwinoutputconfig.XXXXXXXX")
trap 'rm -f -- "$pending"' EXIT
install -o "$uid" -g "$gid" -m 600 -- "$generated" "$pending"
mv -f -- "$pending" "$target"
printf '已写入：%s\n' "$target"
printf '下次显示登录界面时验证；本次不会重启登录服务。\n'
ROOT
}
