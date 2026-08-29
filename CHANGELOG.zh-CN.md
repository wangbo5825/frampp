# 变更日志

FRAMPP 的重要变更记录。

## [0.6.0] - 2026-08-29

### 新增

- 新增安装后统一布局：软件模块移入 `modules/`，配置集中到 `etc/`，运行时数据由
  `data/` 改为 `var/`。
- `bin/` 新增统一命令包装：`php`（兼容标准 PHP CLI）、`composer`、`python`、
  `pip`、`mysql`、`redis-cli` 等，并提供 `env` 脚本设置 `PATH` / `FRAMPP_HOME` /
  `PHPRC`；Linux 使用符号链接，Windows 使用 `.cmd` 包装。
- 新增 Linux systemd 服务：`etc/frampp.service`、`bin/framppd` 与
  `bin/install-systemd`（安装 / 卸载服务）。
- 升级 `caddy-access-filter` 至 v1.2.0，支持本地 IP / CIDR / 国家地区码规则与
  GeoIP 数据库；控制面板新增 IP 访问控制管理（规则、默认策略、热重载）。

### 变更

- 卸载脚本移至 `bin/uninstall`；移除安装后无用的根目录 `install.sh` 与构建脚本，
  `.run` 改为直接调用 `bin/frampp init`。
- 安装提示统一改为中英双语。
- FRAMPP 版本号提升至 `0.6.0`。

## [0.5.0] - 2026-08-24

### 新增

- 新增单镜像 all-in-one Docker 镜像（`Dockerfile`、`docker-compose.yml`），复用
  Linux x86_64 `.run` 载荷，以非 root 用户运行、首启动初始化并提供健康检查。
- 新增 Docker 入口 / 健康检查脚本与 `installer/scripts/build-docker.ps1` 辅助脚本。
- 新增 CI 的 Docker 构建、冒烟测试及 tag 发布时推送到 GitHub Container Registry。

### 变更

- Linux 自解压安装器新增 `--extract-only`，`install.sh` 新增 `--skip-start`，
  使同一安装包可用于构建镜像且不在镜像中烘焙密钥。
- FrankenPHP 改为 musl 完全静态构建（不依赖 glibc），MariaDB 以 glibc 2.31 为
  基线编译并移除 libaio 依赖，使 Linux 包可在 Ubuntu 20.04+、Debian 11+ 以及
  RHEL 9 / Rocky 9 / Alma 9+ 上运行。
- FRAMPP 版本号提升至 `0.5.0`。

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
