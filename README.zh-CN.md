# FRAMPP

**FRAMPP = FrankenPHP + Redis + Agent（MCP）+ MySQL + PHP + Python**

FRAMPP 是面向现代 PHP 开发者的一键安装、开箱即用运行环境与开发平台。它延续
LAMPP / XAMPP / NMPP 的产品形态，并内置基于 MCP 的 AI Agent 接入层。

[English](README.md) · [蓝图](docs/blueprint.md) ·
[版本发布](https://github.com/wangbo5825/frampp/releases)

## 当前状态

- 里程碑：**M4 生产模式 + Linux x86_64 / Docker 变体**
- 最新版本线：**0.6.x**
- 当前通道：PHP **8.5** / FrankenPHP **1.12.7**

## FRAMPP 是什么？

FRAMPP 把 PHP 应用服务器、MariaDB 和 Redis 打包成自包含的 XAMPP 风格安装包：
下载、运行，几分钟即可开始开发。

它面向希望零门槛本地环境的普通开发者，不提供多 PHP 版本并存的 Laragon / Herd
式高级方案。每个版本按「FRAMPP 版本 × 组件通道 × 环境」发布。

## 特性

- **自包含** — FrankenPHP 内置 Caddy、自动 HTTPS、worker 模式，以及
  APCu / redis / mysqli 等扩展。
- **Docker 就绪** — 同样的技术栈也发布为单个公开 Docker 镜像，支持
  `docker run` / Docker Compose 一键启动。
- **AI 就绪** — 内置 Agent / MCP 服务器，将 MySQL、Redis、日志和环境信息开放
  给主流 AI 编码工具。
- **一条命令管理** — `frampp {status|start|stop|cleanup|logs|new-project|ip-access}`，并提供 Web
  控制面板（服务、IP 访问控制、站点管理）。
- **标准布局与命令** — `bin/` 统一命令、`etc/` 集中配置、`var/` 运行时数据、
  `modules/` 软件模块；Linux 目录可整体移动，移动后运行 `bin/frampp init`。
- **默认安全** — 服务仅监听 localhost、每次安装生成随机密钥、使用只读数据库
  账号并保留审计日志。
- **IP 访问控制** — Linux FrankenPHP 构建集成 `caddy-access-filter` v1.2.0，
  支持本地 IP / CIDR / 国家地区码规则与 GeoIP，控制面板可在线管理并热重载。

## 组件

| 字母 | 组件 | 角色 |
| --- | --- | --- |
| F | FrankenPHP | 应用服务器：内置 Caddy、HTTPS、worker 模式 |
| R | Redis | 缓存、队列、会话 |
| A | Agent | MCP 服务器，连接 AI Agent 与本地环境 |
| M | MySQL / MariaDB | 关系数据库，默认 MariaDB |
| P | PHP | 主要开发语言 |
| P | Python | 支撑语言，用于自动化与 AI 负载 |

## 快速开始

### Windows

从 [GitHub Releases](https://github.com/wangbo5825/frampp/releases) 下载
`frampp-setup-8.5-0.6.0-windows-x64.exe`，双击安装。安装器会自动初始化并启动
整套环境。

### Linux

```bash
chmod +x frampp-setup-8.5-0.6.0-linux-x86_64.run
./frampp-setup-8.5-0.6.0-linux-x86_64.run
./frampp-setup-8.5-0.6.0-linux-x86_64.run --prefix /opt/frampp
```

安装完成后：

- 默认站点：<http://127.0.0.1:8080/>
- 控制面板：<http://127.0.0.1:8081/>——服务、IP 访问控制与站点管理（`sites.php`），支持 PHP / 静态 / 反向代理站点并热重载。
- 管理命令：`~/frampp/bin/frampp {status|start|stop|cleanup|logs|new-project|ip-access}`
- 标准命令：`bin/php`、`bin/composer`、`bin/python`、`bin/pip`、`bin/mysql`、
  `bin/redis-cli`；环境变量可 `source bin/env` 一次性配置。
- systemd：`sudo bin/install-systemd` 安装开机自启服务。

### Docker

同样的自包含技术栈也发布为单个公开 Docker 镜像，无需安装任何组件即可启动：

```bash
docker run -d --name frampp \
  -p 8080:8080 -p 8081:8081 \
  -v frampp-data:/opt/frampp/var \
  -v frampp-logs:/opt/frampp/logs \
  -v frampp-htdocs:/opt/frampp/htdocs \
  ghcr.io/wangbo5825/frampp:0.6.0
```

也可使用仓库中的 Docker Compose：

```bash
docker compose up -d
```

容器首次启动会初始化运行时（生成随机密钥、MariaDB 数据目录和配置），随后启动
FrankenPHP、MariaDB 与 Redis。默认站点 <http://127.0.0.1:8080/>，控制面板
<http://127.0.0.1:8081/>。卷、端口和源码构建方式见 [docs/docker.md](docs/docker.md)。

## 系统要求

- **Windows**：x64，Windows 10 / 11（及 Windows Server 2016+）。
- **Linux（x86_64）**：任意 glibc ≥ 2.31 的发行版（Ubuntu 20.04+、Debian 11+、
  RHEL 9 / Rocky 9 / Alma 9+）。FrankenPHP 与 Redis 为完全静态的 musl 二进制
  （不依赖 glibc），MariaDB 以 glibc 2.31 为基线编译且不依赖 libaio。
- **Docker**：任意安装 Docker 引擎的主机；镜像基于 `debian:bookworm-slim`。

CI 在冒烟测试中断言该可移植性（`PORTABLE_OK`：FrankenPHP 静态 + MariaDB
GLIBC ≤ 2.31）。详见 [docs/releases.md](docs/releases.md)。

## 文档

- [蓝图](docs/blueprint.md)
- [版本发布](docs/releases.md)
- [安装 / 升级](docs/upgrade.md)
- [安装器](installer/README.md)
- [Agent](agent/README.md)
- [Docker](docs/docker.md)

## 许可证

[MIT](LICENSE)
