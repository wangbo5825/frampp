# docs/

本目录分两类：**`docs/` 为开发者文档**（蓝图、决策记录、发布流程，不随安装包发布）；
**`docs/user/` 为用户文档**（安装 / 升级 / Docker 使用，随安装包发布到 `docs/`）。

This directory is split into **developer docs** (`docs/`, not shipped) and
**user docs** (`docs/user/`, shipped with the installers under `docs/`).

## English

- Root `README.md` — project overview, quick start and links
- Root `CHANGELOG.md` — release history
- `blueprint.md` — project blueprint & decision records (M0 committed)
- `releases.md` — release process & installer naming (M4)
- `0.6.0-plan.md` — v0.6.0 improvement plan (status: implemented)
- `user/` — **user documentation shipped with installers**: `README.md`
  (requirements / verification / ports), `upgrade.md` (install / upgrade /
  uninstall), `docker.md` (Docker usage)
- Planned: architecture, security baseline

## 中文

- 根目录 `README.zh-CN.md` — 项目概览、快速开始与链接
- 根目录 `CHANGELOG.zh-CN.md` — 版本历史
- `blueprint.md` — 项目蓝图与决策记录（M0 入库）
- `releases.md` — 版本发布流程与安装包命名（M4）
- `0.6.0-plan.md` — v0.6.0 改进计划（状态：已实施）
- `user/` — **随安装包发布的用户文档**：`README.md`（系统要求 / 校验 / 端口）、
  `upgrade.md`（安装 / 升级 / 卸载）、`docker.md`（Docker 使用）
- 后续：架构、安全基线
