#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# CachyOS / Arch 用户级字体设置。普通用户运行，不要 sudo 整个脚本。

CONFIG_FILE="$CONFIG_HOME/fontconfig/conf.d/60-cachyos-fonts.conf"
UI_FONT='Sarasa UI SC'
MONO_FONT='Sarasa Term SC'
RGBA=none
FONT_SIZE=11

validate_options() {
    case "$RGBA" in none|rgb|bgr|vrgb|vbgr) ;; *) die '无效的 rgba' ;; esac
    [[ "$FONT_SIZE" =~ ^(9|1[0-8])$ ]] || die '字号必须是 9..18 的整数'
}

install_fonts() {
    need pacman; need sudo; need fc-cache
    local package
    local -a flags=(--needed)
    for package in ttf-sarasa-gothic noto-fonts-cjk noto-fonts-emoji; do
        if pacman -Q "$package" >/dev/null 2>&1; then flags=(); break; fi
    done
    printf '将更新系统并安装官方字体包；pacman 会显示清单并询问确认。\n'
    # Arch 不支持局部升级；不使用 -Sy，也不需要 AUR helper。
    sudo pacman -Syu "${flags[@]}" ttf-sarasa-gothic noto-fonts-cjk noto-fonts-emoji
    fc-cache -f
    printf '字体安装完成。\n'
}

has_family() {
    # fc-match 会回退到其他字体，不能用它判断字体是否已安装。
    fc-list -f '%{family}\n' | tr ',' '\n' | awk -v family="$1" '
        $0 == family { found=1 } END { exit !found }'
}

print_config() {
    cat <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <!-- Managed by cachyos-setup -->
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>$RGBA</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
  </match>
  <!-- 只关闭轮廓字体的内嵌位图，保留 Noto Color Emoji 等位图彩色字体。 -->
  <match target="font">
    <test name="outline"><bool>true</bool></test>
    <edit name="embeddedbitmap" mode="assign"><bool>false</bool></edit>
  </match>

EOF
    # 仅针对泛型请求选择地区字形，保留明确指定的字体。
    local lang region sarasa_region generic family
    for lang in zh-tw zh-hk ja ko; do
        case "$lang" in zh-tw) region=TC ;; zh-hk) region=HK ;; ja) region=JP ;; ko) region=KR ;; esac
        case "$lang" in zh-tw) sarasa_region=TC ;; zh-hk) sarasa_region=HC ;; ja) sarasa_region=J ;; ko) sarasa_region=K ;; esac
        for generic in sans-serif serif monospace; do
            case "$generic" in
                sans-serif) family="Sarasa UI $sarasa_region" ;;
                serif) family="Noto Serif CJK $region" ;;
                monospace) family="Sarasa Term $sarasa_region" ;;
            esac
            cat <<EOF
  <match target="pattern">
    <test name="family" qual="any"><string>$generic</string></test>
    <test name="lang" compare="contains"><string>$lang</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>$family</string></edit>
  </match>
EOF
        done
    done
    cat <<EOF
  <alias binding="strong">
    <family>sans-serif</family>
    <prefer><family>$UI_FONT</family><family>Noto Sans CJK SC</family><family>Noto Sans</family></prefer>
  </alias>
  <alias binding="strong">
    <family>serif</family>
    <prefer><family>Noto Serif CJK SC</family><family>Noto Serif</family></prefer>
  </alias>
  <alias binding="strong">
    <family>monospace</family>
    <prefer><family>$MONO_FONT</family><family>Noto Sans Mono CJK SC</family><family>Noto Sans Mono</family></prefer>
  </alias>
  <alias binding="strong">
    <family>emoji</family><prefer><family>Noto Color Emoji</family></prefer>
  </alias>
</fontconfig>
EOF
}


apply_config() {
    need fc-list; need fc-cache
    local family kde=false
    for family in "$UI_FONT" "$MONO_FONT" 'Noto Serif CJK SC' 'Noto Color Emoji'; do
        has_family "$family" || die "缺少字体 $family，请确认应用以安装缺失字体"
    done
    if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]]; then need kwriteconfig6; kde=true; fi

    mkdir -p "$(dirname "$CONFIG_FILE")"
    # 同目录临时文件再重命名，不截断已有文件或跟随其符号链接。
    local temporary
    temporary=$(mktemp "$(dirname "$CONFIG_FILE")/.font-setup-XXXXXX")
    print_config > "$temporary"
    mv -f -- "$temporary" "$CONFIG_FILE"
    if "$kde"; then
        local key font="$UI_FONT,$FONT_SIZE,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
        for key in font menuFont toolBarFont; do
            kwriteconfig6 --file "$CONFIG_HOME/kdeglobals" --group General --key "$key" "$font"
        done
        kwriteconfig6 --file "$CONFIG_HOME/kdeglobals" --group General --key fixed "$MONO_FONT,$FONT_SIZE,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
        kwriteconfig6 --file "$CONFIG_HOME/kdeglobals" --group General --key smallestReadableFont "$UI_FONT,$((FONT_SIZE-2)),-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
        kwriteconfig6 --file "$CONFIG_HOME/kdeglobals" --group WM --key activeFont "$font"
        # KDE 上游 FontAASettingsStore::save() 使用这些键，不带连字符。
        kwriteconfig6 --file "$CONFIG_HOME/kdeglobals" --group General --key XftAntialias --type bool true
        kwriteconfig6 --file "$CONFIG_HOME/kdeglobals" --group General --key XftHintStyle hintslight
        kwriteconfig6 --file "$CONFIG_HOME/kdeglobals" --group General --key XftSubPixel "$RGBA"
    fi
    fc-cache -f
    printf '已应用更纱 / %s / %spt。请注销并重新登录以刷新字体。\n' "$RGBA" "$FONT_SIZE"
    printf '可从状态与恢复菜单回退（含整个 kdeglobals）；应用显式字体需在各自设置中调整。\n'
}

TARGETS=("$CONFIG_FILE" "$CONFIG_HOME/kdeglobals")

feature_options() {
    local existing size family
    if [[ -f "$CONFIG_FILE" ]] && command -v python3 >/dev/null; then
        existing=$(python3 "$APP_ROOT/lib/fontconfig.py" rgba "$CONFIG_FILE") || existing=''
        case "$existing" in none|rgb|bgr|vrgb|vbgr) RGBA=$existing ;; esac
        if command -v kreadconfig6 >/dev/null; then
            existing=$(kreadconfig6 --file "$CONFIG_HOME/kdeglobals" --group General --key font)
            IFS=, read -r family size _ <<< "$existing"
            if [[ "$family" == "$UI_FONT" && "$size" =~ ^(9|1[0-8])$ ]]; then FONT_SIZE=$size; fi
        fi
    fi
    while (($#)); do
        (($# >= 2)) || die "$1 缺少值"
        case "$1" in --size) FONT_SIZE=$2 ;; --rgba) RGBA=$2 ;; *) die "未知字体选项：$1" ;; esac
        shift 2
    done
    validate_options
}

fonts_available() {
    local family
    command -v fc-list >/dev/null || return 1
    for family in "$UI_FONT" "$MONO_FONT" 'Noto Serif CJK SC' 'Noto Color Emoji'; do
        has_family "$family" || return 1
    done
}

fonts_ready() {
    command -v python3 >/dev/null || return 1
    [[ -f "$CONFIG_FILE" ]] && python3 "$APP_ROOT/lib/fontconfig.py" check "$CONFIG_FILE" <(print_config) || return 1
    [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] || return 0
    command -v kreadconfig6 >/dev/null || return 1
    local key value expected font="$UI_FONT,$FONT_SIZE,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    for key in font menuFont toolBarFont fixed smallestReadableFont XftAntialias XftHintStyle XftSubPixel; do
        case "$key" in
            fixed) expected="$MONO_FONT,$FONT_SIZE,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" ;;
            smallestReadableFont) expected="$UI_FONT,$((FONT_SIZE-2)),-1,5,400,0,0,0,0,0,0,0,0,0,0,1" ;;
            XftAntialias) expected=true ;; XftHintStyle) expected=hintslight ;; XftSubPixel) expected=$RGBA ;;
            *) expected=$font ;;
        esac
        value=$(kreadconfig6 --file "$CONFIG_HOME/kdeglobals" --group General --key "$key")
        [[ "$value" == "$expected" ]] || return 1
    done
    [[ $(kreadconfig6 --file "$CONFIG_HOME/kdeglobals" --group WM --key activeFont) == "$font" ]]
}

feature_status() {
    if ! command -v python3 >/dev/null; then printf '无法检查（缺少 python3）\n';
    elif ! command -v fc-list >/dev/null; then printf '无法检查（缺少 fontconfig）\n';
    elif ! fonts_available; then printf '缺少依赖（更纱或 Noto 字体）\n';
    elif fonts_ready; then printf '配置就绪（%spt / %s）\n' "$FONT_SIZE" "$RGBA";
    elif [[ ! -e "$CONFIG_FILE" ]]; then printf '未配置\n';
    else printf '待应用（与当前预设不同）\n'; fi
}

feature_preview() {
    local target
    for target in "${TARGETS[@]}"; do check_path "$target"; done
    printf '\n字体设置 · 更纱 UI/Term SC / Noto CJK / Emoji\n'
    printf '字号：%spt；次像素渲染：%s（none 为灰度抗锯齿）。\n' "$FONT_SIZE" "$RGBA"
    printf '将修改（kdeglobals 仅在 KDE 下修改）：\n'; show_targets
    if ! fonts_available; then
        printf '自动安装字体：ttf-sarasa-gothic noto-fonts-cjk noto-fonts-emoji；包已安装但字体不可用时重新安装。\n更纱完整包较大；pacman -Syu 包含完整系统升级，并保留确认。\n'
    fi
    printf '应用前备份完整文件；保留已有 fonts.conf、DPI 和桌面缩放。应用后请注销重登。\n'
    if fonts_available && fonts_ready; then printf '当前配置已符合预设，执行时将跳过。\n'; fi
}

feature_apply() {
    local target
    for target in "${TARGETS[@]}"; do check_path "$target"; done
    if fonts_available && fonts_ready; then printf '配置已符合目标，跳过。\n'; return; fi
    if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]]; then need kwriteconfig6; fi
    if ! fonts_available; then install_fonts; fi
    backup_files
    apply_config
    fonts_ready || die '字体配置校验失败'
}
