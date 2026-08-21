# FRAMPP

**FRAMPP = FrankenPHP + Redis + Agent（MCP）+ MySQL + PHP + Python**

FRAMPP 是面向现代 PHP 开发者的一键安装、开箱即用运行环境与开发平台。它延续
LAMPP / XAMPP / NMPP 的产品形态，并内置基于 MCP 的 AI Agent 接入层。

[English](README.md) · [蓝图](docs/blueprint.md) ·
[版本发布](https://github.com/wangbo5825/frampp/releases)

## 当前状态

- 里程碑：**M4 生产模式 + Linux x86_64 变体**
- 最新版本线：**0.4.x**
- 当前通道：PHP **8.5** / FrankenPHP **1.12.7**

## FRAMPP 是什么？

FRAMPP 把 PHP 应用服务器、MariaDB 和 Redis 打包成自包含的 XAMPP 风格安装包：
下载、运行，几分钟即可开始开发。

它面向希望零门槛本地环境的普通开发者，不提供多 PHP 版本并存的 Laragon / Herd
式高级方案。每个版本按「FRAMPP 版本 × 组件通道 × 环境」发布。

## 特性

- **自包含** — FrankenPHP 内置 Caddy、自动 HTTPS、worker 模式，以及
  APCu / redis / mysqli 等扩展。
- **AI 就绪** — 内置 Agent / MCP 服务器，将 MySQL、Redis、日志和环境信息开放
  给主流 AI 编码工具。
- **一条命令管理** — `frampp {status|start|stop|logs|new-project}`，并提供 Web
  控制面板。
- **Linux 目录可整体移动** — 默认安装到 `~/frampp`，无需 root。
- **默认安全** — 服务仅监听 localhost、每次安装生成随机密钥、使用只读数据库
  账号并保留审计日志。
- **Caddy access/filter 钩子** — Linux FrankenPHP 构建集成
  `caddy-access-filter`，支持代理前 `access` 与代理后 `filter` 两个可编程阶段，
  由外部 HTTP 处理器完成业务裁决与响应加工。

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
`frampp-setup-8.5-0.4.0-windows-x64.exe`，双击安装。安装器会自动初始化并启动
整套环境。

### Linux

```bash
chmod +x frampp-setup-8.5-0.4.0-linux-x86_64.run
./frampp-setup-8.5-0.4.0-linux-x86_64.run
./frampp-setup-8.5-0.4.0-linux-x86_64.run --prefix /opt/frampp
```

安装完成后：

- 默认站点：<http://127.0.0.1:8080/>
- 控制面板：<http://127.0.0.1:8081/>
- 管理命令：`~/frampp/bin/frampp {status|start|stop|logs|new-project}`

## 文档

- [蓝图](docs/blueprint.md)
- [版本发布](docs/releases.md)
- [安装 / 升级](docs/upgrade.md)
- [安装器](installer/README.md)
- [Agent](agent/README.md)

## 许可证

[MIT](LICENSE)
