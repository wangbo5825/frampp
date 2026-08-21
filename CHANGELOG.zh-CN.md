# 变更日志

FRAMPP 的重要变更记录。

## [0.4.0] - 2026-08-21

### 新增

- 在 Linux FrankenPHP 定制构建中集成 `caddy-access-filter` v1.0.0。
- 新增独立的中英文根文档文件
  （`README.md`、`README.zh-CN.md`、`CHANGELOG.md`、`CHANGELOG.zh-CN.md`）。

### 变更

- FRAMPP 版本号提升至 `0.4.0`。
- 在蓝图与版本发布文档中记录新增的 Caddy 模块。

## [0.3.0] - 2026-08-21

### 变更

- 通过源码编译 MariaDB、定制构建 FrankenPHP 并启用 UPX，以及内置精简
  Python 3.13 运行时，缩减 Linux 安装包体积。
- 删除 Python `include/`、`share/`、Tcl/Tk 原生库与开发文件，同时保留 pip。
- 在 Linux 安装包组装时保留 Python 软链接。

## [0.2.0] - 2026-08-20

### 新增

- 新增 Linux x86_64 的 XAMPP 风格 `.run` 安装器。
- 新增静态 Redis 构建与 Linux 运行时初始化脚本。

## [0.1.0] - 2026-08-19

### 新增

- 初始 Windows 运行时：FrankenPHP、MariaDB、Redis、APCu 与控制面板。
- Agent / MCP 服务器与双语项目主页。
