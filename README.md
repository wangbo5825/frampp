# FRAMPP

**FRAMPP = FrankenPHP + Redis + Agent + MySQL + PHP + Python**

面向现代 PHP 开发者的“一键安装、开箱即用”运行环境与开发平台，延续 LAMPP / XAMPP / NMPP 的产品形态，内置 AI Agent 接入层（MCP）。

> 当前里程碑：M0（仓库落地）。完整设计见 [docs/blueprint.md](docs/blueprint.md)。

## 组件

| 字母 | 组件 | 角色 |
| --- | --- | --- |
| F | FrankenPHP | 应用服务器（内置 Caddy、自动 HTTPS、worker 模式） |
| R | Redis | 分布式缓存 / 队列 / 会话 |
| A | Agent | MCP 服务器：对接 AI Agent 的工具接入层 |
| M | MySQL | 关系数据库 |
| P | PHP | 主要开发语言 |
| P | Python | 支撑语言：自动化 / AI 负载（可选组件） |

## 开发

- 平台：Windows 优先，Linux / macOS / Docker 为后续里程碑
- 开发约定见 [AGENTS.md](AGENTS.md)
- 里程碑 M0–M5 见 [docs/blueprint.md](docs/blueprint.md)

## 许可证

[MIT](LICENSE)
