#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
source "$APP_ROOT/modules/gaming.sh"

feature_options() {
    read_settings
    local explicit_anti=false option
    if [[ "$CONFIG_VALID" != true ]]; then
        [[ "$local_action" == status ]] && return
        die '已有游戏配置无效，请先修正'
    fi
    if [[ "$local_action" != status ]]; then
        if ! has_proton; then SETTINGS[LOW_LATENCY_LAYER]=1; fi
        SETTINGS[PROTON_ENABLE_WAYLAND]=${SETTINGS[PROTON_ENABLE_WAYLAND]:-1}
        SETTINGS[PROTON_DXVK_LOWLATENCY]=${SETTINGS[PROTON_DXVK_LOWLATENCY]:-1}
        SETTINGS[DXVK_FRAME_PACE]=${SETTINGS[DXVK_FRAME_PACE]:-low-latency-vrr}
        SETTINGS[DXVK_FRAME_RATE]=${SETTINGS[DXVK_FRAME_RATE]:-${SETTINGS[VKD3D_FRAME_RATE]:-117}}
        SETTINGS[VKD3D_FRAME_RATE]=${SETTINGS[VKD3D_FRAME_RATE]:-${SETTINGS[DXVK_FRAME_RATE]}}
        SETTINGS[MESA_SHADER_CACHE_MAX_SIZE]=${SETTINGS[MESA_SHADER_CACHE_MAX_SIZE]:-12G}
    fi
    while (($#)); do
        option=$1; shift
        case "$option" in
            --fps|--cache-size)
                (($# >= 1)) || die "$option 缺少值"
                if [[ "$option" == --fps ]]; then SETTINGS[DXVK_FRAME_RATE]=$1; SETTINGS[VKD3D_FRAME_RATE]=$1;
                else SETTINGS[MESA_SHADER_CACHE_MAX_SIZE]=$1; fi
                shift ;;
            --anti-lag-layer) SETTINGS[LOW_LATENCY_LAYER]=1; explicit_anti=true ;;
            --no-anti-lag-layer) unset 'SETTINGS[LOW_LATENCY_LAYER]' ;;
            --dx12-lowlatency) SETTINGS[PROTON_VKD3D_LOWLATENCY]=1 ;;
            --no-dx12-lowlatency) unset 'SETTINGS[PROTON_VKD3D_LOWLATENCY]' ;;
            --fsr-indicator) SETTINGS[PROTON_FSR4_INDICATOR]=1 ;;
            --no-fsr-indicator) unset 'SETTINGS[PROTON_FSR4_INDICATOR]' ;;
            *) die "未知 Proton 选项：$option" ;;
        esac
    done
    if [[ ${SETTINGS[PROTON_VKD3D_LOWLATENCY]:-} == 1 ]]; then
        [[ "$explicit_anti" == false ]] || die 'Anti-Lag 层不能与实验性 VKD3D 低延迟同时启用'
        unset 'SETTINGS[LOW_LATENCY_LAYER]'
    fi
    steam_config_lines <(print_config) >/dev/null || die '游戏参数无效'
}

feature_status() {
    if [[ "$CONFIG_VALID" != true ]]; then printf '配置不完整（参数无效）\n';
    elif ! has_proton; then printf '未配置\n';
    elif ! proton_complete; then printf '配置不完整（缺少基础参数）\n';
    elif ! command -v python3 >/dev/null; then printf '无法检查（缺少 python3）\n';
    elif integration_ready; then printf '配置就绪（%s FPS；游戏效果需实测）\n' "${SETTINGS[DXVK_FRAME_RATE]}";
    else printf '配置不完整（Steam 入口缺失或需要更新）\n'; fi
}

feature_preview() {
    printf '\nProton 全局预设\n'
    preview_gaming
    printf '117 FPS 适用于原预设的 120Hz VRR 环境，可用 --fps 调整。\n'
    printf 'Wayland、低延迟和 Anti-Lag 取决于 Proton/游戏支持；不强制 HDR 或 FSR。\n'
    if [[ ${SETTINGS[PROTON_VKD3D_LOWLATENCY]:-} == 1 ]]; then
        printf '实验性 VKD3D 低延迟：不搭配 Anti-Lag 2 或帧生成。\n'
    fi
}
feature_apply() { apply_gaming; }
