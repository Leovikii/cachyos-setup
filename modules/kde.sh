#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# KDE 外观：Breeze + Klassy 装饰 + Catppuccin Mocha + Papirus-Dark + Bibata。

SCRIPT_DIR=$APP_ROOT/assets
SCHEME=CatppuccinMochaPink
CURSOR=Bibata-Modern-Ice
COMPONENTS=(breeze klassy colors papirus bibata)
DATA_DIRS=()
IFS=: read -r -a DATA_DIRS <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
DATA_DIRS=("$DATA_HOME" "${DATA_DIRS[@]}")
PLUGIN_ROOT=''
DECORATION_DIR=''

detect_plugins() {
    PLUGIN_ROOT=''
    DECORATION_DIR=''
    local tool
    for tool in qtpaths6 /usr/lib/qt6/bin/qtpaths6 /usr/lib/qt6/bin/qtpaths; do
        if command -v "$tool" >/dev/null 2>&1; then
            PLUGIN_ROOT=$("$tool" --plugin-dir)
            break
        fi
    done
    [[ -n "$PLUGIN_ROOT" ]] || return 0
    # 以本机原生 Breeze 插件确定 ABI，不把旧 KDecoration2 插件当成新版可用组件。
    local abi
    for abi in 3 2; do
        if [[ -f "$PLUGIN_ROOT/org.kde.kdecoration$abi/org.kde.breeze.so" ]]; then
            DECORATION_DIR="$PLUGIN_ROOT/org.kde.kdecoration$abi"
            break
        fi
    done
}

data_file() {
    local root
    for root in "${DATA_DIRS[@]}"; do
        if [[ -f "$root/$1" ]]; then printf '%s\n' "$root/$1"; return 0; fi
    done
    return 1
}

has_component() {
    case "$1" in
        breeze)
            [[ -f "$PLUGIN_ROOT/styles/breeze6.so" && -n "$DECORATION_DIR" ]] &&
                data_file plasma/desktoptheme/default/metadata.json >/dev/null ;;
        klassy) [[ -n "$DECORATION_DIR" && -f "$DECORATION_DIR/org.kde.klassy.so" ]] ;;
        papirus) data_file icons/Papirus-Dark/index.theme >/dev/null ;;
        bibata)
            # Qt 的图标搜索路径包含传统 ~/.icons。
            [[ -f "$HOME/.icons/$CURSOR/index.theme" && -f "$HOME/.icons/$CURSOR/cursors/left_ptr" ]] ||
                { data_file "icons/$CURSOR/index.theme" >/dev/null && data_file "icons/$CURSOR/cursors/left_ptr" >/dev/null; } ;;
        colors) data_file "color-schemes/$SCHEME.colors" >/dev/null ;;
    esac
}

read_setting() {
    kreadconfig6 --file "$CONFIG_HOME/$1" --group "$2" --key "$3" --default "${4:-}"
}

targets() {
    # 最后一列是未显式配置时的 KDE 默认值。
    cat <<EOF
kdeglobals|KDE|widgetStyle|Breeze|Breeze
plasmarc|Theme|name|default|default
kdeglobals|Icons|Theme|Papirus-Dark|breeze
kdeglobals|General|accentColorFromWallpaper|false|false
kdeglobals|General|AccentColor|0,0,0,0|0,0,0,0
kdeglobals|General|ColorScheme|$SCHEME|BreezeLight
kcminputrc|Mouse|cursorTheme|$CURSOR|breeze_cursors
kwinrc|org.kde.kdecoration2|library|org.kde.klassy|org.kde.breeze
kwinrc|org.kde.kdecoration2|theme|Klassy|Breeze
kwinrc|org.kde.kdecoration2|NoPlugin|false|false
EOF
}

install_components() {
    need pacman
    local part package helper='' candidate
    local -a repo=() aur=() repo_flags=(--needed) aur_flags=(--needed)
    for part in "${COMPONENTS[@]}"; do
        [[ "$part" != colors ]] || continue
        if has_component "$part"; then printf '跳过已有组件：%s\n' "$part"; continue; fi
        case "$part" in
            breeze) package=breeze ;;
            klassy) package=klassy ;;
            papirus) package=papirus-icon-theme ;;
            bibata) package=bibata-cursor-theme ;;
        esac
        if pacman -Q "$package" >/dev/null 2>&1 ||
            { [[ "$part" == bibata ]] && pacman -Q bibata-cursor-theme-bin >/dev/null 2>&1; }; then
            printf '%s 已安装但组件不可用，将重新安装仓库包或重新构建 AUR 包。\n' "$package"
            repo_flags=()
            aur_flags=(--rebuild)
        fi
        if pacman -Si "$package" >/dev/null 2>&1; then
            repo+=("$package")
        else
            case "$part" in
                klassy) aur+=(klassy) ;;
                bibata) aur+=(bibata-cursor-theme-bin) ;;
                *) die "当前仓库没有 $package，请先检查软件源" ;;
            esac
        fi
    done
    # CachyOS 仓库提供 paru；AUR 构建始终由当前普通用户执行。
    if ((${#aur[@]})); then
        for candidate in paru yay; do
            if command -v "$candidate" >/dev/null 2>&1; then helper=$candidate; break; fi
        done
        if [[ -z "$helper" ]]; then
            repo+=(paru)
            helper=paru
        fi
        for package in base-devel git; do
            if ! pacman -Q "$package" >/dev/null 2>&1; then repo+=("$package"); fi
        done
    fi
    if ((${#repo[@]})); then
        printf '安装缺少的仓库包并完整升级系统：%s\n' "${repo[*]}"
        run_pacman -Syu "${repo_flags[@]}" "${repo[@]}"
    fi
    if ((${#aur[@]})); then
        need "$helper"
        printf '通过 %s 安装缺少的 AUR 包并升级；请审阅 PKGBUILD：%s\n' "$helper" "${aur[*]}"
        "$helper" -Syu "${aur_flags[@]}" "${aur[@]}"
    fi
    if has_component colors; then
        printf '跳过已有配色：%s\n' "$SCHEME"
    else
        [[ -f "$SCRIPT_DIR/kde/$SCHEME.colors" ]] || die '缺少随仓库附带的 .colors 文件，请下载完整仓库'
        mkdir -p "$DATA_HOME/color-schemes"
        [[ ! -L "$DATA_HOME/color-schemes/$SCHEME.colors" ]] || die '配色目标是符号链接，拒绝覆盖'
        cp -p -- "$SCRIPT_DIR/kde/$SCHEME.colors" "$DATA_HOME/color-schemes/$SCHEME.colors"
    fi
    detect_plugins
    for part in "${COMPONENTS[@]}"; do
        has_component "$part" || die "安装后仍找不到可用的 $part；未应用任何主题配置"
    done
    printf '所选组件已齐全：%s\n' "${COMPONENTS[*]}"
}

write_setting() {
    local file=$1 group=$2 key=$3 value=$4
    if [[ "$(read_setting "$file" "$group" "$key" "${5:-}")" != "$value" ]]; then
        kwriteconfig6 --file "$CONFIG_HOME/$file" --group "$group" --key "$key" --notify "$value"
    fi
}

check_session() {
    feature_applicable ||
        die '请在 Plasma 6 Wayland 会话的终端内应用'
    need qdbus6
}

feature_applicable() {
    [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* && "${KDE_SESSION_VERSION:-}" == 6 && "${XDG_SESSION_TYPE:-}" == wayland ]]
}

apply_config() {
    check_session
    local tool part file group key value fallback current
    for tool in kreadconfig6 kwriteconfig6; do need "$tool"; done
    need plasma-apply-colorscheme
    need plasma-apply-desktoptheme
    need plasma-apply-cursortheme
    for part in "${COMPONENTS[@]}"; do
        has_component "$part" || die "缺少可用的 $part，安装后仍不可用；未修改外观配置"
    done
    local changed=false recolor=false
    while IFS='|' read -r file group key value fallback; do
        current=$(read_setting "$file" "$group" "$key" "$fallback")
        if [[ "$current" != "$value" ]]; then
            printf '将设置 %s [%s] %s：%s → %s\n' "$file" "$group" "$key" "$current" "$value"
            changed=true
            [[ "$group" != General ]] || recolor=true
        fi
    done < <(targets)
    if ! "$changed"; then printf '所选配置已符合目标，跳过写入和备份。\n'; return; fi
    qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation >/dev/null
    mkdir -p "$CONFIG_HOME"
    write_setting kdeglobals General accentColorFromWallpaper false false
    write_setting kdeglobals General AccentColor 0,0,0,0 0,0,0,0
    if [[ "$(read_setting kdeglobals General ColorScheme BreezeLight)" != "$SCHEME" ]]; then
        plasma-apply-colorscheme "$SCHEME"
    elif "$recolor"; then
        # KDE CLI 的 --accent-color 分支不切换配色，必须在正确配色上单独调用。
        plasma-apply-colorscheme --accent-color transparent
    fi
    if [[ "$(read_setting plasmarc Theme name default)" != default ]]; then
        plasma-apply-desktoptheme default
    fi
    if [[ "$(read_setting kcminputrc Mouse cursorTheme breeze_cursors)" != "$CURSOR" ]]; then
        local size
        size=$(read_setting kcminputrc Mouse cursorSize)
        plasma-apply-cursortheme "$CURSOR"
        # 部分版本的工具会重置尺寸；保留原设置（含未指定尺寸的情况）。
        if [[ -n "$size" ]]; then
            write_setting kcminputrc Mouse cursorSize "$size"
        else
            kwriteconfig6 --file "$CONFIG_HOME/kcminputrc" --group Mouse --key cursorSize --delete
        fi
    fi
    while IFS='|' read -r file group key value fallback; do
        write_setting "$file" "$group" "$key" "$value" "$fallback"
    done < <(targets)
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure
    while IFS='|' read -r file group key value fallback; do
        [[ "$(read_setting "$file" "$group" "$key" "$fallback")" == "$value" ]] || die "配置校验失败：$file [$group] $key；可从状态与恢复菜单恢复"
    done < <(targets)
    printf '已应用：%s\n建议注销重登，让所有应用同步外观；不会自动重启桌面。\n' "${COMPONENTS[*]}"
}

TARGETS=("$CONFIG_HOME/kdeglobals" "$CONFIG_HOME/plasmarc" "$CONFIG_HOME/kcminputrc" "$CONFIG_HOME/kwinrc" "$DATA_HOME/color-schemes/$SCHEME.colors")

feature_options() { (($# == 0)) || die 'KDE 外观不接受额外参数'; detect_plugins; }

kde_ready() {
    local part file group key value fallback
    for part in "${COMPONENTS[@]}"; do has_component "$part" || return 1; done
    while IFS='|' read -r file group key value fallback; do
        [[ "$(read_setting "$file" "$group" "$key" "$fallback")" == "$value" ]] || return 1
    done < <(targets)
}

feature_status() {
    if ! command -v kreadconfig6 >/dev/null; then printf '无法检查（缺少 kreadconfig6）\n'; return; fi
    local part
    for part in "${COMPONENTS[@]}"; do
        if ! has_component "$part"; then printf '缺少依赖（%s）\n' "$part"; return; fi
    done
    if kde_ready; then printf '配置就绪（外观仍需在桌面确认）\n'; else printf '待应用\n'; fi
}

feature_preview() {
    local target part missing=false
    feature_applicable || die '请在 Plasma 6 Wayland 会话的终端内应用'
    for target in "${TARGETS[@]}"; do check_path "$target"; done
    printf '\nKDE 外观 · Breeze / Klassy / Mocha Pink / Papirus-Dark / Bibata\n'
    printf '范围：当前用户的 Plasma 6 Wayland 桌面；保留布局、字体、缩放和光标尺寸。\n'
    printf '将检查并修改以下文件（配色仅在缺少时复制）：\n'; show_targets
    printf '缺失组件：'
    for part in "${COMPONENTS[@]}"; do
        if ! has_component "$part"; then printf ' %s' "$part"; missing=true; fi
    done
    if ! "$missing"; then printf ' 无'; fi
    printf '\n缺失组件通过 pacman 或 paru/yay 自动安装；需要 AUR 时自动安装 paru（无现有 helper 时）、base-devel 和 git。\n包含完整系统/AUR 升级，保留包管理器确认和 PKGBUILD 审阅。\n'
    printf '已安装但所需文件或 ABI 不可用时，自动重新安装或构建；组件校验通过后才应用外观。\n'
    printf '应用前保存完整文件快照；整文件恢复会覆盖后续修改。建议应用后注销重登。\n'
    if command -v kreadconfig6 >/dev/null && kde_ready; then printf '当前配置已符合预设，执行时将跳过。\n'; fi
}

feature_apply() {
    local target
    for target in "${TARGETS[@]}"; do check_path "$target"; done
    if command -v kreadconfig6 >/dev/null && kde_ready; then printf '配置已符合目标，跳过。\n'; return; fi
    check_session
    need kreadconfig6; need kwriteconfig6
    qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation >/dev/null
    backup_files
    install_components
    apply_config
}
