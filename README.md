# CachyOS Setup

面向 **CachyOS · KDE Plasma 6 Wayland** 的个人初始化预设。

- **桌面美化**：KDE 外观、更纱字体。
- **游戏设置**：Proton 用户级全局预设、飞智黑武士 5 Pro 按 Xbox 360 分类。
- **系统微调**：登录界面仅显示主屏（仅 Plasma Login Manager）、安装跳过测速（仅 Live ISO，固定官方 CDN）。

## 使用

以桌面普通用户下载并运行最新版，**不要 sudo 整个脚本**：

```bash
curl -fL https://github.com/Leovikii/cachyos-setup/releases/latest/download/cachyos-setup.sh -o cachyos-setup.sh && bash cachyos-setup.sh
```

或使用 wget：

```bash
wget https://github.com/Leovikii/cachyos-setup/releases/latest/download/cachyos-setup.sh -O cachyos-setup.sh && bash cachyos-setup.sh
```

每项功能先展示修改内容，确认后自动安装所需依赖并应用配置。三个功能分类内均有“安装全部”，一次确认后顺序执行适用项，遇错停止。不适用项会注明并跳过；软件安装包含完整系统升级，保留包管理器确认。菜单还提供状态检查、配置恢复和脚本更新。

再次运行使用 `bash cachyos-setup.sh`，命令行用法见 `bash cachyos-setup.sh --help`。

游戏预设需匹配所用 Proton 和游戏；默认 117 FPS。应用后按提示重启 Steam 或注销重登。

安装跳过测速：先从 Live ISO 欢迎界面打开安装器，停留在配置页面，再运行本脚本应用该项，随后直接继续安装。重新从欢迎界面启动安装器会覆盖测速脚本，需再次应用。镜像列表会复制到目标系统；本功能不修改安装后的测速定时器。

## 许可

[GPL-3.0](LICENSE)。附带的 Catppuccin 配色遵循其[上游 MIT 许可](assets/kde/LICENSE.catppuccin)。
