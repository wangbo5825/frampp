# FRAMPP

**FRAMPP = FrankenPHP + Redis + Agent + MySQL + PHP + Python**

面向现代 PHP 开发者的"一键安装、开箱即用"运行环境与开发平台，延续 LAMPP / XAMPP / NMPP 的产品形态，内置 AI Agent 接入层（MCP）。

One-click, out-of-the-box runtime & dev platform for modern PHP developers, following the LAMPP / XAMPP / NMPP tradition, with a built-in AI Agent layer (MCP).

> 当前里程碑 / Current milestone：**M1 核心运行时（已实现并可本地运行）/ Core runtime (implemented, runs locally)**。
> 完整设计见 / Full design: [docs/blueprint.md](docs/blueprint.md)。

## 简介 / About

FRAMPP 把 Web 开发三件套（PHP 应用服务器 + MariaDB + Redis）打包成自包含的安装包：下载、运行、即可开始开发。安装无需 root / 管理员权限，不依赖系统包管理器，目录可整体移动。

FRAMPP bundles the web-dev stack (PHP app server + MariaDB + Redis) into self-contained installers: download, run, and start developing. No root/admin required, no system package manager dependencies, and the directory is relocatable.

## 组件 / Components

| 字母 / Letter | 组件 / Component | 角色 / Role |
| --- | --- | --- |
| F | FrankenPHP | 应用服务器（内置 Caddy、自动 HTTPS、worker 模式）/ App server (embedded Caddy, auto HTTPS, worker mode) |
| R | Redis | 分布式缓存 / 队列 / 会话 / Cache / queue / sessions |
| A | Agent | MCP 服务器：对接 AI Agent 的工具接入层 / MCP server: tool layer for AI agents |
| M | MySQL / MariaDB | 关系数据库（默认发行 MariaDB）/ Relational database (MariaDB by default) |
| P | PHP | 主要开发语言 / Primary language |
| P | Python | 支撑语言：自动化 / AI 负载（可选组件）/ Supporting language: automation / AI workloads (optional) |

## 快速开始 / Quick Start

### Windows

```powershell
# 下载 / Download: frampp-setup-8.5-<version>-windows-x64.exe（GitHub Releases）
# 双击安装，完成后自动初始化并启动 / double-click to install; auto init & start

# 开发预览（从源码运行）/ Dev preview (run from source)
powershell -ExecutionPolicy Bypass -File installer/scripts/download.ps1   # 下载并校验组件 / fetch & verify components
powershell -ExecutionPolicy Bypass -File installer/scripts/init.ps1       # 初始化运行时 / init runtime
php control-panel/bin/frampp start all                                    # 启动 / start
php control-panel/bin/frampp status                                       # 状态 / status
php control-panel/bin/frampp stop all                                     # 停止 / stop
```

### Linux（x86_64，一键安装包 / one-click installer）

```bash
# 下载 / Download: frampp-setup-8.5-<version>-linux-x86_64.run（GitHub Releases）
chmod +x frampp-setup-8.5-<version>-linux-x86_64.run
./frampp-setup-8.5-<version>-linux-x86_64.run                              # 默认安装到 ~/frampp / installs to ~/frampp
./frampp-setup-8.5-<version>-linux-x86_64.run --prefix /opt/frampp         # 指定目录 / custom directory
```

安装器会自动校验完整性、解压并执行初始化（随机密钥 / MariaDB 数据目录）与启动，然后打印地址。
The installer verifies integrity, extracts, initializes (random secrets / MariaDB datadir), starts all services, and prints the URLs.

运行后访问 / After install, visit:

- 默认站点 / Default site: <http://127.0.0.1:8080/>
- 控制面板 / Control panel: <http://127.0.0.1:8081/>
- 管理命令 / Manage: `~/frampp/bin/frampp {status|start|stop|logs|new-project}`

Linux 包自包含 FrankenPHP（静态构建，内置 APCu/Redis/mysqli 扩展）、MariaDB、Redis（官方源码静态编译），不依赖系统包管理器；目录可整体移动（移动后重新运行 `install.sh`）。
The Linux package bundles FrankenPHP (static build with APCu/Redis/mysqli built in), MariaDB and Redis (static build from upstream source) — no system packages needed; the directory is relocatable (re-run `install.sh` after moving).

## 发布 / Releases

类似 XAMPP，按 FRAMPP 版本 × 组件通道 × 环境发布一键安装包 / Like XAMPP, installers are published per FRAMPP version × component channel × environment:

- Windows：`frampp-setup-8.5-<version>-windows-x64.exe`
- Linux：`frampp-setup-8.5-<version>-linux-x86_64.run`

下载与校验见 / Download & verify: [GitHub Releases](https://github.com/wangbo5825/frampp/releases) · 发布流程 / release process: [docs/releases.md](docs/releases.md)。

## 文档 / Documentation

- 开发指南 / Dev guide: [AGENTS.md](AGENTS.md)
- 蓝图与里程碑 / Blueprint & milestones: [docs/blueprint.md](docs/blueprint.md)
- 版本发布 / Releases: [docs/releases.md](docs/releases.md)

## 许可证 / License

[MIT](LICENSE)
