#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
source "$APP_ROOT/modules/gaming.sh"

feature_options() {
    (($# == 0)) || die '手柄分类不接受额外参数'
    read_settings
    if [[ "$local_action" != status ]]; then
        [[ "$CONFIG_VALID" == true ]] || die '已有游戏配置无效，请先修正'
        SETTINGS[SDL_GAMECONTROLLERTYPE]='0x37d7/0x2401=Xbox360'
    fi
}

feature_status() {
    if [[ "$CONFIG_VALID" != true ]]; then printf '配置不完整（参数无效）\n';
    elif [[ ${SETTINGS[SDL_GAMECONTROLLERTYPE]:-} != '0x37d7/0x2401=Xbox360' ]]; then printf '未配置\n';
    elif ! command -v python3 >/dev/null; then printf '无法检查（缺少 python3）\n';
    elif integration_ready; then printf '配置就绪（实际分类需在 Steam 确认）\n';
    else printf '配置不完整（Steam 入口缺失或需要更新）\n'; fi
}

feature_preview() {
    printf '\n黑武士 5 Pro → Xbox 360 · SDL 手柄分类\n'
    preview_gaming
    printf '仅覆盖 37d7:2401 的分类，可在设备未连接时应用；其它连接模式的 ID 可能不同。\n'
    printf '不会关闭 Steam Input、替换驱动或提供背键/陀螺仪功能。\n'
}
feature_apply() { apply_gaming; }
