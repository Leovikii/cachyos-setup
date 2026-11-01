#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
STATE_ROOT=${XDG_STATE_HOME:-$HOME/.local/state}/cachyos-setup

die() { printf '错误：%s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }
confirm() {
    local answer
    IFS= read -r -p "${1:-确认应用？}[y/N] › " answer || return 1
    [[ "$answer" == y || "$answer" == Y || "$answer" == yes || "$answer" == YES ]]
}

check_path() {
    local path=$1
    [[ "$path" == /* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || die "路径必须为不含换行的绝对路径：$path"
    [[ "/${path#/}/" != *'/../'* && "/${path#/}/" != *'/./'* ]] || die "路径不能含 . 或 ..：$path"
    [[ ! -e "$path" || -f "$path" ]] || die "目标不是普通文件：$path"
    while [[ "$path" != / ]]; do
        [[ ! -L "$path" ]] || die "拒绝写入符号链接路径：$path"
        path=$(dirname -- "$path")
    done
}

lock_operation() {
    need flock
    check_path "$STATE_ROOT/lock"
    mkdir -p -- "$STATE_ROOT"
    exec 9> "$STATE_ROOT/lock"
    flock -n 9 || die '另一个配置操作正在进行'
}

backup_files() {
    local target index=0 directory
    for target in "${TARGETS[@]}"; do check_path "$target"; done
    check_path "$STATE_ROOT/latest"
    check_path "$STATE_ROOT/backups/.check"
    umask 077
    mkdir -p -- "$STATE_ROOT/backups"
    directory=$(mktemp -d "$STATE_ROOT/backups/$(date +%Y%m%d-%H%M%S)-XXXXXX")
    printf '%s\n' "$MODULE" > "$directory/module"
    printf '%s\n' "$APP_VERSION" > "$directory/version"
    printf '%s\n' "${TARGETS[@]}" > "$directory/targets"
    for target in "${TARGETS[@]}"; do
        if [[ -f "$target" ]]; then cp -p -- "$target" "$directory/$index";
        else touch "$directory/$index.absent"; fi
        index=$((index+1))
    done
    printf '%s\n' "${directory##*/}" > "$STATE_ROOT/latest"
    printf '已备份：%s\n' "$directory"
}

atomic_install() {
    local source=$1 target=$2 mode=${3:-644} temporary
    check_path "$target"
    if [[ -f "$target" ]] && cmp -s -- "$source" "$target" && [[ $(stat -c %a -- "$target") == "$mode" ]]; then return; fi
    mkdir -p -- "$(dirname -- "$target")"
    temporary=$(mktemp "$(dirname -- "$target")/.cachyos-setup-XXXXXX")
    if ! install -m "$mode" -- "$source" "$temporary"; then rm -f -- "$temporary"; return 1; fi
    mv -fT -- "$temporary" "$target"
    printf '已更新：%s\n' "$target"
}

show_targets() { printf '  %s\n' "${TARGETS[@]}"; }

restore_latest() {
    local id directory module index=0 target
    local -a saved=()
    [[ -f "$STATE_ROOT/latest" ]] || die '没有用户配置备份'
    check_path "$STATE_ROOT/latest"
    IFS= read -r id < "$STATE_ROOT/latest"
    [[ "$id" =~ ^[0-9]{8}-[0-9]{6}-[[:alnum:]]{6}$ ]] || die '备份索引无效'
    directory="$STATE_ROOT/backups/$id"
    check_path "$directory/module"
    check_path "$directory/targets"
    check_path "$directory/version"
    IFS= read -r module < "$directory/module"
    valid_module "$module" || die "此备份不受当前版本支持，原始文件仍保留在：$directory"
    [[ "$module" != login-screen ]] || die '登录界面备份需按应用时输出的命令恢复'
    [[ "$module" != install-mirrors ]] || die '安装跳过测速备份需按应用时输出的 sudo 命令恢复'
    # 仅接受当前模块声明的目标路径，不执行备份中的代码或任意路径。
    MODULE=$module
    source "$APP_ROOT/modules/$module.sh"
    mapfile -t saved < "$directory/targets"
    [[ ${#saved[@]} == ${#TARGETS[@]} ]] || die '备份目标数量不匹配'
    for target in "${TARGETS[@]}"; do
        [[ "$target" == "${saved[index]}" ]] || die '备份路径与当前 HOME/XDG 不匹配'
        check_path "$target"
        check_path "$directory/$index"
        check_path "$directory/$index.absent"
        [[ -f "$directory/$index" || -f "$directory/$index.absent" ]] || die "备份不完整：$target"
        index=$((index+1))
    done
    printf '\n恢复快照：%s\n模块：%s · 脚本版本：%s\n将恢复或删除以下完整文件：\n' "$id" "$(module_label "$module")" "$(< "$directory/version")"
    show_targets
    printf '注意：这些文件在备份之后的其它修改也会被覆盖；已安装软件保留。\n'
    if ! confirm '确认恢复？'; then printf '已取消。\n'; return; fi
    ((EUID != 0)) || die '请以桌面普通用户运行'
    lock_operation
    index=0
    for target in "${TARGETS[@]}"; do
        if [[ -f "$directory/$index" ]]; then
            atomic_install "$directory/$index" "$target" "$(stat -c %a -- "$directory/$index")"
        else rm -f -- "$target"; fi
        index=$((index+1))
    done
    printf '已恢复。请注销重登；游戏设置还需完全退出并重新启动 Steam。\n'
}
