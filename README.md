# FRAMPP

**FRAMPP = FrankenPHP + Redis + Agent (MCP) + MySQL + PHP + Python**

**One-click, out-of-the-box runtime & development platform for modern PHP developers — following the LAMPP / XAMPP / NMPP tradition, with a built-in AI Agent layer (MCP).**

> Current milestone: **M1 Core Runtime (implemented and runs locally)** — FrankenPHP + MySQL + Redis + APCu, plus a control-panel MVP (start / stop / status / ports / logs).
> Full design & decision records: [docs/blueprint.md](docs/blueprint.md).

---

## English (Primary)

### What is FRAMPP?

FRAMPP bundles the complete web-development stack — PHP application server, MariaDB and Redis — into self-contained, XAMPP-style installers. Download an installer, run it, and start developing within minutes.

We focus on **everyday developers who want a zero-friction local environment**, not power users who need multiple PHP versions running side by side (Laragon / Herd style). Like XAMPP, FRAMPP publishes a different one-click installer for each FRAMPP version × component channel × environment.

Key characteristics:

- **Self-contained** — FrankenPHP (embedded Caddy, automatic HTTPS, worker mode, built-in APCu / redis / mysqli extensions), MariaDB and Redis are all bundled; no system package manager dependencies.
- **No admin required** — installs under `~/frampp` on Linux and a per-user directory on Windows; no root / administrator privileges.
- **Relocatable** — the whole directory can be moved; on Linux just re-run `install.sh` after moving.
- **One-command management** — `frampp {status|start|stop|logs|new-project}` plus a web control panel.
- **AI-ready** — a built-in Agent (MCP) layer lets AI assistants interact with your local stack through standard MCP tools.
- **Secure by default** — services bind to localhost, runtime secrets are generated per installation, read-only database accounts are used where applicable, and audit logs are kept.
- **Bilingual** — English-first documentation with complete Chinese translations.

### Components

| Letter | Component | Role |
| --- | --- | --- |
| F | FrankenPHP | Application server — embedded Caddy, automatic HTTPS, worker mode |
| R | Redis | Cache / queue / sessions |
| A | Agent | MCP server — the tool layer that connects AI agents to your stack |
| M | MySQL / MariaDB | Relational database (MariaDB by default) |
| P | PHP | Primary language |
| P | Python | Supporting language — automation and AI workloads (optional, embedded lightweight runtime) |

### Quick Start

#### Windows

```powershell
# Download frampp-setup-8.5-<version>-windows-x64.exe from GitHub Releases,
# then double-click to install; the installer initializes and starts the stack automatically.

# Dev preview (run from source)
powershell -ExecutionPolicy Bypass -File installer/scripts/download.ps1   # fetch & verify components
powershell -ExecutionPolicy Bypass -File installer/scripts/init.ps1       # init runtime
php control-panel/bin/frampp start all                                    # start
php control-panel/bin/frampp status                                       # status
php control-panel/bin/frampp stop all                                     # stop
```

#### Linux (x86_64, one-click installer)

```bash
# Download frampp-setup-8.5-<version>-linux-x86_64.run from GitHub Releases
chmod +x frampp-setup-8.5-<version>-linux-x86_64.run
./frampp-setup-8.5-<version>-linux-x86_64.run                              # installs to ~/frampp
./frampp-setup-8.5-<version>-linux-x86_64.run --prefix /opt/frampp         # custom directory
```

The installer verifies package integrity, extracts the bundle, initializes the runtime (random secrets, MariaDB data directory) and starts all services, then prints the URLs.

After install, visit:

- Default site: <http://127.0.0.1:8080/>
- Control panel: <http://127.0.0.1:8081/>
- Manage: `~/frampp/bin/frampp {status|start|stop|logs|new-project}`

The Linux package bundles static FrankenPHP (APCu / redis / mysqli built in), MariaDB and statically compiled Redis — no system packages required; the directory is relocatable (re-run `install.sh` after moving).

### Releases

Like XAMPP, installers are published per FRAMPP version × component channel × environment:

- Windows: `frampp-setup-8.5-<version>-windows-x64.exe`
- Linux: `frampp-setup-8.5-<version>-linux-x86_64.run`

Download & verify: [GitHub Releases](https://github.com/wangbo5825/frampp/releases) · Release process: [docs/releases.md](docs/releases.md).

### Documentation

- Project site (EN/ZH toggle): <https://wangbo5825.github.io/frampp/>
- Dev guide: [AGENTS.md](AGENTS.md)
- Blueprint & milestones: [docs/blueprint.md](docs/blueprint.md)
- Releases: [docs/releases.md](docs/releases.md)

### License

[MIT](LICENSE)

---

## 中文

### FRAMPP 是什么？

FRAMPP 把完整的 Web 开发环境（PHP 应用服务器 + MariaDB + Redis）打包成自包含的 XAMPP 风格安装包：下载、运行，几分钟即可开始开发。

我们面向**希望零门槛本地环境的普通开发者**，不提供多 PHP 版本并存的 Laragon / Herd 式高级方案。与 XAMPP 类似，FRAMPP 按「FRAMPP 版本 × 组件通道 × 环境」发布不同的一键安装包。

核心特点：

- **自包含** — 内置 FrankenPHP（含 Caddy、自动 HTTPS、worker 模式及 APCu / redis / mysqli 扩展）、MariaDB、Redis，不依赖系统包管理器
- **无需管理员权限** — Linux 默认安装到 `~/frampp`，Windows 按用户目录安装
- **目录可整体移动** — Linux 移动后重跑 `install.sh` 即可
- **一条命令管理** — `frampp {status|start|stop|logs|new-project}` + Web 控制面板
- **AI 就绪** — 内置 Agent（MCP）层，让 AI 助手通过标准 MCP 工具操作本地环境
- **默认安全** — 服务仅监听 localhost、每次安装生成随机密钥、按需使用只读数据库账号、保留审计日志
- **双语文档** — 英文优先，附完整中文说明

### 组件

| 字母 | 组件 | 角色 |
| --- | --- | --- |
| F | FrankenPHP | 应用服务器（内置 Caddy、自动 HTTPS、worker 模式） |
| R | Redis | 缓存 / 队列 / 会话 |
| A | Agent | MCP 服务器 — AI Agent 与本地环境的工具接入层 |
| M | MySQL / MariaDB | 关系数据库（默认发行 MariaDB） |
| P | PHP | 主要开发语言 |
| P | Python | 支撑语言 — 自动化与 AI 负载（可选、嵌入式轻量运行时） |

### 快速开始

#### Windows

```powershell
# 从 GitHub Releases 下载 frampp-setup-8.5-<version>-windows-x64.exe，
# 双击安装，安装器会自动初始化并启动整套环境。

# 开发预览（从源码运行）
powershell -ExecutionPolicy Bypass -File installer/scripts/download.ps1   # 下载并校验组件
powershell -ExecutionPolicy Bypass -File installer/scripts/init.ps1       # 初始化运行时
php control-panel/bin/frampp start all                                    # 启动
php control-panel/bin/frampp status                                       # 状态
php control-panel/bin/frampp stop all                                     # 停止
```

#### Linux（x86_64，一键安装包）

```bash
# 从 GitHub Releases 下载 frampp-setup-8.5-<version>-linux-x86_64.run
chmod +x frampp-setup-8.5-<version>-linux-x86_64.run
./frampp-setup-8.5-<version>-linux-x86_64.run                              # 默认安装到 ~/frampp
./frampp-setup-8.5-<version>-linux-x86_64.run --prefix /opt/frampp         # 指定目录
```

安装器会自动校验完整性、解压、初始化（随机密钥 / MariaDB 数据目录）并启动全部服务，最后打印访问地址。

安装完成后访问：

- 默认站点：<http://127.0.0.1:8080/>
- 控制面板：<http://127.0.0.1:8081/>
- 管理命令：`~/frampp/bin/frampp {status|start|stop|logs|new-project}`

Linux 包自包含静态构建的 FrankenPHP（内置 APCu / redis / mysqli）、MariaDB 与静态编译的 Redis，不依赖系统包管理器；目录可整体移动（移动后重跑 `install.sh`）。

### 发布

与 XAMPP 类似，按「FRAMPP 版本 × 组件通道 × 环境」发布一键安装包：

- Windows：`frampp-setup-8.5-<version>-windows-x64.exe`
- Linux：`frampp-setup-8.5-<version>-linux-x86_64.run`

下载与校验见：[GitHub Releases](https://github.com/wangbo5825/frampp/releases) · 发布流程：[docs/releases.md](docs/releases.md)。

### 文档

- 项目主页（中英切换）：<https://wangbo5825.github.io/frampp/>
- 开发指南：[AGENTS.md](AGENTS.md)
- 蓝图与里程碑：[docs/blueprint.md](docs/blueprint.md)
- 版本发布：[docs/releases.md](docs/releases.md)

### 许可证

[MIT](LICENSE)
