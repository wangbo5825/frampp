# AGENTS.md — FRAMPP 开发指南

本文件是 Codex 等编码代理在本仓库工作的入口说明。开始任何任务前，请先阅读 [docs/blueprint.md](docs/blueprint.md)。

## 项目一句话

FRAMPP = FrankenPHP + Redis + Agent(MCP) + MySQL + PHP + Python：面向现代 PHP 开发者的“一键安装、开箱即用”运行环境与开发平台。

## 当前状态

- 当前里程碑：**M0（仓库落地）**
- 下一步：**M1 核心运行时**——FrankenPHP + MySQL + Redis + APCu 打包，控制面板 MVP（启停 / 状态 / 端口 / 日志）

## 目录约定

| 目录 | 内容 |
| --- | --- |
| `src/php/` | PHP 组件源码（MCP server、控制面板后端） |
| `src/python/` | Python 辅助组件 |
| `agent/` | Agent / MCP 服务器（独立可复用包） |
| `control-panel/` | 控制面板 |
| `installer/` | 安装器与打包配置 |
| `templates/` | 项目模板（API Platform starter、PHP 最小工程） |
| `dist/` | 第三方二进制（**禁止提交**，由脚本下载） |
| `tests/` | 单元 / 集成 / 端到端测试 |
| `docs/` | 蓝图与设计文档 |

## 规则

1. **不向 `dist/` 提交第三方二进制**；大文件一律由安装器 / 构建脚本下载并校验哈希。
2. 影响架构的决策先更新 `docs/blueprint.md` 的决策记录，再动手。
3. 提交信息使用英文，遵循 Conventional Commits（`feat` / `fix` / `docs` / `chore` / …）。
4. 默认目标平台为 Windows；涉及跨平台行为时在 CI 矩阵（ubuntu + windows）中验证。
5. 修改代码后必须通过对应测试，或至少执行 `php -l` 语法检查。
6. 安全基线（localhost 绑定、只读账号、命令白名单、审计日志）是硬性要求，不允许为方便而放宽。

## 常用命令

- 语法检查：`php -l <file>`
- CI：`.github/workflows/ci.yml`（push / PR 自动执行）
