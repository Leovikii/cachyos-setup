# CachyOS Setup

面向 **CachyOS · KDE Plasma 6 Wayland** 的个人初始化预设。

- **桌面美化**：KDE 外观、更纱字体。
- **游戏设置**：Proton 用户级全局预设、飞智黑武士 5 Pro 按 Xbox 360 分类。
- **系统微调**：登录界面仅显示主屏（仅 Plasma Login Manager）。

## 使用

以桌面普通用户下载并运行最新版，**不要 sudo 整个脚本**：

```bash
curl -fL https://github.com/Leovikii/cachyos-setup/releases/latest/download/cachyos-setup.sh -o cachyos-setup.sh && bash cachyos-setup.sh
```

或使用 wget：

```bash
wget https://github.com/Leovikii/cachyos-setup/releases/latest/download/cachyos-setup.sh -O cachyos-setup.sh && bash cachyos-setup.sh
```

每项功能先展示修改内容，确认后执行。菜单提供状态检查、配置恢复和脚本更新；缺少软件时安装可能包含系统升级。再次运行使用 `bash cachyos-setup.sh`，命令行用法见 `bash cachyos-setup.sh --help`。

游戏预设需匹配所用 Proton 和游戏；默认 117 FPS。应用后按提示重启 Steam 或注销重登。

## 许可

[GPL-3.0](LICENSE)。附带的 Catppuccin 配色遵循其[上游 MIT 许可](assets/kde/LICENSE.catppuccin)。
