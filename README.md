# FRAMPP

**FRAMPP = FrankenPHP + Redis + Agent + MySQL + PHP + Python**

面向现代 PHP 开发者的“一键安装、开箱即用”运行环境与开发平台，延续 LAMPP / XAMPP / NMPP 的产品形态，内置 AI Agent 接入层（MCP）。

> 当前里程碑：**M1 核心运行时（已实现并可本地运行）**。完整设计见 [docs/blueprint.md](docs/blueprint.md)。

## 组件

| 字母 | 组件 | 角色 |
| --- | --- | --- |
| F | FrankenPHP | 应用服务器（内置 Caddy、自动 HTTPS、worker 模式） |
| R | Redis | 分布式缓存 / 队列 / 会话 |
| A | Agent | MCP 服务器：对接 AI Agent 的工具接入层 |
| M | MySQL / MariaDB | 关系数据库（默认发行 MariaDB） |
| P | PHP | 主要开发语言 |
| P | Python | 支撑语言：自动化 / AI 负载（可选组件） |

## 开发

- 平台：Windows x64 与 Linux x86_64（自包含一键包）；macOS / Docker 为后续里程碑
- 开发约定见 [AGENTS.md](AGENTS.md)
- 里程碑 M0–M5 见 [docs/blueprint.md](docs/blueprint.md)

## 快速开始（开发预览）

```powershell
# 1. 下载并校验组件（FrankenPHP / MariaDB / Redis / Composer / APCu，版本与哈希锁定）
powershell -ExecutionPolicy Bypass -File installer/scripts/download.ps1

# 2. 初始化运行时（解压、生成配置与随机密钥、初始化 MariaDB 数据目录）
powershell -ExecutionPolicy Bypass -File installer/scripts/init.ps1

# 3. 启动全部服务（或用控制面板 CLI 管理单个服务）
php control-panel/bin/frampp start all
php control-panel/bin/frampp status
php control-panel/bin/frampp stop all
```

启动后访问：

- 默认站点：http://127.0.0.1:8080/
- 控制面板：http://127.0.0.1:8081/

## Linux 快速开始（一键安装包）

```bash
tar -xzf frampp-setup-8.5-0.2.0-linux-x86_64.tar.gz
cd frampp
./install.sh        # 自动初始化（随机密钥 / MariaDB 数据目录）并启动三件套
./bin/frampp status # 管理命令：status / start / stop / logs / new-project
```

Linux 包自包含 FrankenPHP（静态构建，内置 APCu/Redis/mysqli 扩展）、MariaDB、Redis（官方源码静态编译），
不依赖系统包管理器；目录可整体移动。

## 发布（一键安装包）

类似 XAMPP，按 FRAMPP 版本 × 组件通道 × 环境发布安装包：

- Windows：`frampp-setup-8.5-0.2.0-windows-x64.exe`
- Linux：`frampp-setup-8.5-0.2.0-linux-x86_64.tar.gz`

下载与校验见 [GitHub Releases](https://github.com/wangbo5825/frampp/releases)，流程见 [docs/releases.md](docs/releases.md)。

## 许可证

[MIT](LICENSE)
