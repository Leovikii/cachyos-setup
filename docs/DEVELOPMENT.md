# 第一版开发约定

## 范围

版本从 `0.1.0` 开始，`VERSION` 是唯一版本来源。普通用户通过 `bash setup.sh` 进入中文菜单，也可使用命令行；内部模块不作为独立用户入口。

第一版迁移以下功能：

| 菜单 | 模块 | 预设 |
| --- | --- | --- |
| 桌面美化 | KDE 外观 | Breeze、Klassy、Catppuccin Mocha Pink、Papirus-Dark、Bibata Modern Ice |
| 桌面美化 | 字体设置 | 更纱 UI/Term SC、Noto CJK/Emoji，11pt、灰度抗锯齿 |
| 游戏设置 | Proton 全局预设 | 用户级 Wayland、DXVK 低延迟、VRR 帧节奏、117 FPS、12G Mesa 缓存、可选 Anti-Lag 层 |
| 游戏设置 | 黑武士 5 Pro → Xbox 360 | SDL 对 `37d7:2401` 的分类覆盖；可在未连接时应用 |
| 系统微调 | 登录界面仅显示主屏 | 仅支持 Plasma Login Manager + KWin Wayland |
| 系统微调 | 安装跳过测速 | 仅 CachyOS Live ISO；跳过 Calamares 测速，固定 CachyOS CDN77 和官方 Arch CDN |

不迁移 USB 唤醒/WOL，不做自动硬件调优、游戏效果判定、动态插件框架或无人值守执行。

## 目录与职责

- `setup.sh`：唯一入口、参数校验、模块隔离执行。
- `lib/common.sh`：路径检查、确认、用户配置备份与恢复。
- `lib/dependencies.sh`：按功能检查命令和 Steam 入口，预览缺失包，确认后自动安装并复查。
- `lib/menu.sh`：主菜单、二级菜单、状态与恢复。
- `lib/update.sh`：Git 克隆仓库的检查与确认更新。
- `lib/fontconfig.py`：只读解析 Fontconfig XML，比较配置内容而非排版与注释。
- `modules/`：`kde.sh`、`fonts.sh`、`proton.sh`、`controller.sh`、`login-screen.sh`、`install-mirrors.sh`，另用 `gaming.sh` 共享游戏参数逻辑。
- `assets/kde/`：固定配色与许可证；`assets/steam/`：共享环境解析器、运行时启动器。
- `tests/`：临时 HOME、假命令和独立 Git 仓库测试。
- `scripts/package.sh`：从指定提交生成自包含的 `cachyos-setup.sh`，以明文 heredoc 嵌入模块、资源与许可证；运行时写入私有临时目录，退出清理，不下载运行依赖文件。

模块在独立子 Shell 中加载，共用函数不必实现复杂命名空间。保留旧脚本的依赖检查、KDecoration ABI 检查、严格参数解析和错误处理，移除重复入口、菜单与独立备份代码。

## 操作流程

1. 只读检测依赖、目标文件和配置。
2. 预览预设、需安装的软件、将写入的文件、影响范围、生效方式与备份策略。
3. 普通用户明确输入 `y/yes` 后执行；回车或 EOF 取消。不得在确认前安装、写配置或创建状态目录。
4. 确认后先自动安装缺失执行依赖，再重新读取选项及检查现场，最后应用配置。缺失包使用 pacman/AUR 正常交互安装；需要安装时包含完整升级，不使用 `--noconfirm`。预览不能因缺少 Python/Qt 等可安装依赖而提前退出；依赖补齐后必须复查，失败不得写配置。基础运行环境为 CachyOS 的 Bash 与基础系统工具。
5. 修改前备份，内容一致跳过。失败停止，保留备份并输出恢复提示，不假装完成或自动重启桌面。
6. 校验写入结果，提示重新启动 Steam、注销或重启后的验证方式。

状态根据实际内容和依赖判断，使用“配置就绪 / 未配置 / 配置不完整 / 缺少依赖 / 无法检查”等文字，不依靠历史成功标记。第一版不把进程环境或游戏效果作为菜单状态的依据。参数合法且安装入口完整才能认为游戏配置就绪；用户自定义合法 FPS 等值保留。

每个功能分类菜单提供“安装全部”，CLI 对应 `--apply-all desktop|gaming|system`。先筛选会话、登录管理器或 Live 身份适用项并逐项预览；一次脚本确认后顺序执行，包管理器仍正常询问。各项保持独立备份，失败即停止，已完成项不自动回滚。配置损坏和未知文件不能作为“不适用”静默跳过。每项执行前重新读取共享配置，避免后执行模块覆盖先执行模块的设置。

执行依赖映射使用 Arch/CachyOS 包名，包括 Python、KConfig、Qt 工具、Fontconfig、util-linux、diffutils 和 procps-ng；缺少原生 Steam 入口时自动安装 `steam`。没有 sudo 时使用 pkexec 或 su 安装 sudo，随后复查。KDE 的缺失主题优先从仓库安装；需要 AUR 时自动补齐 `base-devel`、`git`，无现有 paru/yay 时从 CachyOS 仓库安装 paru。AUR 构建在普通用户身份下执行并保留 PKGBUILD 审阅。

字体、窗口装饰、图标和光标本身也是脚本的安装对象。检测到包已安装但字体/组件不可用时，移除该次安装的 `--needed` 以允许重装；AUR 使用 `--rebuild` 重新构建。安装后仍严格检查字体族、主题文件和 KDecoration ABI，不在组件不可用时写入外观配置，也不以要求用户手动下载作为正常安装路径。

字体比较忽略 XML 排版、注释和属性顺序，接受追加的同值无条件渲染规则，保留对参数差异和额外冲突规则的检查；已有字体大小、rgba 不依靠脚本归属标记读取。登录账户私有文件无读取权限时仍显示“无法检查”，状态检测不自动提权。

## 游戏配置

唯一参数源为 `${XDG_CONFIG_HOME:-~/.config}/environment.d/90-cachyos-gaming.conf`。Proton 与手柄分别更新自己的键，保留另一模块的选择；控制器独立应用时不得隐式启用 Proton 预设。

生成用户级 Steam 启动器、共享校验器、KDE 登录加载器和 `steam.desktop`。安装后不依赖仓库路径。环境配置只按白名单解析，不执行 shell 代码。配置属于当前用户会话全局，不写 `/etc/environment`，不改游戏启动选项、Steam 账户或输入布局。

不强制 HDR/FSR，不全局开启 `PROTON_USE_SDL`。Anti-Lag 与实验 VKD3D 低延迟保持互斥。游戏是否支持仍需实测。正式版只使用本仓库配置路径，不包含临时迁移或旧路径识别代码。

## 备份与权限

用户级配置统一备份到 `${XDG_STATE_HOME:-~/.local/state}/cachyos-setup/backups/`，记录模块、版本和原文件不存在的情况。每次只应用一个模块，备份本次涉及的文件；恢复需预览并确认，明确整文件恢复可能覆盖后续改动。拒绝写入符号链接路径或未知归属的游戏入口。

登录管理器文件由内部 sudo 写入，备份保留在登录账户配置目录，并输出恢复命令；第一版不将特权备份纳入用户级自动恢复，菜单明确说明。

安装跳过测速同样使用内部 sudo，在 `/etc/pacman.d/cachyos-setup-install-backup.*` 中备份全部五个文件，保留原权限和归属，输出逐文件恢复命令，不纳入用户配置自动恢复。Live ISO 重启后修改和备份均不保留；镜像列表经安装器复制到目标系统后会保留。

## 安装跳过测速

`install-mirrors` 使用官方欢迎程序同样采用的 `/run/archiso` 作为 Live 环境标记，不要求其 `bootmnt` 子目录。只读解析 `os-release` 的 ID 和 NAME，不执行文件：接受 `ID=cachyos`，或官方 Live ISO 使用的 `ID=arch` 配合 `NAME=CachyOS` / `CachyOS Linux`；普通 Arch Live 不被接受。系统标识不可读显示“无法检查”。只接受已核对的上游 `update-mirrorlist` 命令结构或本模块生成的完整脚本，未知结构、缺失/不可读文件、符号链接均停止。状态检查只读、不提权、不联网；以五个文件的实际内容判断就绪。

先从欢迎界面打开安装器，停在配置页面，再应用本功能。上游 `calamares-online.sh` 会重装 Calamares，故不能在欢迎界面启动流程之前应用，也不要在应用后重新从欢迎界面启动。预览及提权后均检查 Calamares 进程和 pacman 锁；用户必须在真正安装开始前操作，不能仅凭进程存在或没有 pacman 锁断定安装尚未开始。

跳过 `/etc/calamares/scripts/update-mirrorlist` 的联网安装及测速，以成功返回的脚本替换，保留其余安装流程。四份镜像列表只包含一个 Server：CachyOS 使用 `https://cdn77.cachyos.org/repo/$arch/$repo`，v3/v4 分别保留 `$arch_v3`/`$arch_v4`；Arch 使用 `https://archlinux.cachyos.org/repo/$repo/os/$arch`。CDN77 是全球 CDN，不保证美国节点。不测速、不做连通性探测，不卸载测速软件或修改安装后定时器；不可达时由用户恢复或手动换源。

核对依据：[安装器测速入口](https://github.com/CachyOS/cachyos-calamares/blob/cachyos/src/scripts/update-mirrorlist)、[镜像列表复制流程](https://github.com/CachyOS/cachyos-calamares/blob/cachyos/src/modules/shellprocess/shellprocess_initialize_pacman.conf)、[Live ISO 启动器](https://github.com/CachyOS/CachyOS-Live-ISO/blob/master/archiso/airootfs/usr/local/bin/calamares-online.sh)、[官方镜像列表](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/cachyos-mirrorlist/cachyos-mirrorlist)及其 [v3/v4 打包替换规则](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/cachyos-mirrorlist/PKGBUILD)。上游流程改变时重新核对，不通过宽松匹配强行兼容。

2026-11-01，v0.2.0 在 Arch 容器中以普通用户通过 Shell 语法、ShellCheck 及全部 46 项测试，无跳过。新增 10 项测试覆盖安装跳过测速及单文件发行版，使用临时 Live 文件和 sudo/进程命令替身，包含取消、幂等、架构变量、备份恢复、符号链接、权限、提权后复查和部分写入失败；没有执行真实磁盘安装，完整 Live ISO 安装仍需实机验证。

原 v0.2.0 错误要求 `bootmnt` 必须存在，测试又人为创建了该目录，遗漏了实际 Live 启动布局。用户反馈的 2026.08.09 ISO 使用 `copytoram=auto`，`ID=cachyos`，存在 `/run/archiso/airootfs`，却没有 `/run/archiso/bootmnt`，因此被误判为“不适用”。此外，[上游 ISO 配置中的 `ID=arch` 和 `NAME=CachyOS`](https://github.com/CachyOS/CachyOS-Live-ISO/blob/master/archiso/airootfs/etc/os-release)也需要兼容。修复后的安装及单文件发行版测试采用用户实机身份与无 bootmnt 的布局，并另测上游身份、其它 Arch Live、不可读标识及不执行 os-release；Live 标记与[官方欢迎程序配置](https://github.com/CachyOS/CachyOS-Welcome/blob/master/data/preferences.json)一致。

2026-11-01 用户明确要求修复后删除原 v0.2.0 再次发布，因此本次保留 `VERSION=0.2.0`，在修复检查通过后删除旧 Release 和旧标签，再由 Actions 从修复提交重建并重新发布；这是用户授权的同版本重发例外，不更改一般发布规则。

## 版本更新

只在用户选择更新时联网。单文件发行版使用 curl 或 wget 下载 latest Release 脚本及 `SHA256SUMS`，校验摘要、Shell 语法和版本后预览替换路径；用户确认后原子替换当前脚本，保留文件权限，不应用系统配置。校验失败、下载失败、符号链接或检查后本地脚本变化时停止。`CACHYOS_SETUP_SCRIPT` 由发行脚本启动入口传给内部模块，用于定位原文件。

源码仓库仍支持本仓库 `origin` 的 Git 克隆、干净工作区、当前分支跟踪 origin 分支。获取远端后展示版本和提交摘要，用户确认后 `git merge --ff-only` 到已经展示的提交；不自动 stash、reset、切换分支或应用配置。验证目标版本及必需文件，更新后退出，用户重新运行。

## 验证与后续开发

运行 Shell 语法检查、可用时运行 ShellCheck，以及临时目录中的单元/集成测试。重点覆盖菜单 EOF/取消无写入、参数拒绝、共享配置保留、重复执行、备份恢复、符号链接保护、错误退出和 Git 更新限制。测试不得安装包、修改真实 HOME、启动真实 Steam 或重启服务。

```bash
bash scripts/check.sh
```

KDE/字体配置测试使用真实 KConfig 工具，缺少时跳过相应测试；包管理器、D-Bus、桌面应用工具和 sudo 均被替换。Git 更新测试使用临时本地远端，无网络请求。实际视觉效果、Proton 功能、手柄识别及登录屏幕仍需实机验证。

主 README 只面向用户，保持功能与运行命令简短；开发说明放在本文件。主项目采用 GPL-3.0-only，附带配色保留 Catppuccin 的 MIT 许可证，来源为 `catppuccin/kde` 提交 `6606b5179cfc1e9ba5c3b6b70e15c468e2dddca2` 的 `generated/color-schemes/CatppuccinMochaPink.colors`。

添加模块时显式登记入口和菜单，提供检测、预览、应用函数及必要测试。只有实际需要时才扩展公共代码。配置语义发生不兼容改变时再增加迁移机制，不预建配置数据库。

## 首次发行与发布流程

2026-10-31 用户已完成本机迁移并授权清理、推送和首次发行。只读复核确认参数与迁移前备份一致，两个旧文件已移除，新启动器和 KDE 加载入口检查通过；当前没有可读取的 Steam 进程，不宣称游戏效果已验证。临时迁移模块、入口、旧路径状态识别及对应测试已删除，原始用户备份保留。已删除模块的历史快照不再由正式版自动恢复，会显示原始备份位置。

`.github/workflows/release.yml` 在 PR 和 main 推送时，在 Arch 容器安装原生依赖并以普通用户执行完整检查；纯文档改动（Markdown、`docs/` 和许可证）不触发 workflow。main 通过后，由 GitHub Actions 从该次提交构建单文件 `cachyos-setup.sh` 和 `SHA256SUMS`，检查语法并验证独立运行，再创建对应标签及公开 Release。`VERSION` 是版本来源，同版本已发行时跳过，不能移动已有标签；不发布本机测试产物。源码是 Shell/Python，不生成二进制安装器。README 下载链接固定为 `releases/latest/download/cachyos-setup.sh`。

2026-10-31 按用户要求，删除原压缩包发行版及旧标签后，使用同版本 `v0.1.0` 从改版提交重新发布；这是首次发行格式的调整，后续正式版本遵循已有标签不移动的规则。

单文件改版已通过本地及 Actions 的 36 项测试，远端 ShellCheck 与构建通过；公开 latest 下载地址、SHA-256、独立运行的版本/帮助入口均已验证，Release 仅附带脚本与校验文件。

2026-10-31 已通过官方发布记录核对唯一第三方 Action：`actions/checkout v7.0.1`（Node 24），固定其完整提交哈希；更新时核对最新稳定版及运行环境要求。运行器使用 `ubuntu-latest`，Arch 容器通过 `pacman -Syu` 获取当前软件包；最小镜像额外安装 `diffutils`，提供配置比较所需的 `cmp`。
