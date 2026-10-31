# CachyOS Setup

面向 **CachyOS · KDE Plasma 6 Wayland** 的个人初始化预设。

- **桌面美化**：KDE 外观、更纱字体。
- **游戏设置**：Proton 用户级全局预设、飞智黑武士 5 Pro 按 Xbox 360 分类。
- **系统微调**：登录界面仅显示主屏（仅 Plasma Login Manager）。

## 使用

需要 Git。以桌面普通用户运行，**不要 sudo 整个脚本**：

```bash
git clone https://github.com/Leovikii/cachyos-setup.git && cd cachyos-setup && bash setup.sh
```

每项功能先展示修改内容，确认后执行。菜单提供状态检查、配置恢复和脚本更新；缺少软件时安装可能包含系统升级。

已有仓库直接运行 `bash setup.sh`。命令行用法见 `bash setup.sh --help`。

也可从 [Releases](https://github.com/Leovikii/cachyos-setup/releases) 下载脚本包，解压后运行 `bash setup.sh`；归档副本不支持 Git 自更新。

游戏预设需匹配所用 Proton 和游戏；默认 117 FPS。应用后按提示重启 Steam 或注销重登。

## 许可

[GPL-3.0](LICENSE)。附带的 Catppuccin 配色遵循其[上游 MIT 许可](assets/kde/LICENSE.catppuccin)。
