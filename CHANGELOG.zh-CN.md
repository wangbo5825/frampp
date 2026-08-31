# 变更日志

FRAMPP 的重要变更记录。

## [0.7.0] - 2026-08-31

### 新增

- Linux x86_64 数据库组件切换为 **MySQL 8.0.46 Community**，由官方
  glibc 2.17 minimal 包裁剪（`installer/scripts/linux/trim-mysql.sh`）。
  官方构建以 CentOS 7（glibc ≥ 2.17）为目标，OpenSSL（以及 Kerberos /
  LDAP / SASL）打包在 `lib/private`，不依赖 systemd，同一份二进制可运行于
  CentOS 7 与现代发行版；服务端仅需 `libaio`。裁剪删除 `lib/mecab` 词典
  （约 129MB）、Kerberos / LDAP-SASL / OCI / FIDO 认证插件、组复制、
  示例/测试插件、非核心 CLI 工具、头文件、文档及除英文外的本地化错误消息，
  保持模块紧凑。
- 数据库初始化改为 `mysqld --initialize-insecure` + PHP PDO（mysqlnd，走
  unix socket）创建账号，不再依赖 `mysql` CLI（新 Debian/Ubuntu 可能缺
  `libtinfo.so.5`）。密钥字段为 `mysql_root_password` /
  `mysql_readonly_password`（升级的旧运行时会自动补充新密钥）。
- 安装包命名由 `frampp-setup-<channel>-<version>-<env>` 简化为
  **`frampp-<version>-<env>.<ext>`**（如 `frampp-0.7.0-linux-x86_64.run`、
  `frampp-0.7.0-windows-x64.exe`），组件通道在 Release note 中说明。
- Linux 安装包不再包含 `installer/` 目录：运行时脚本移入 `bin/`（init /
  docker-entrypoint / docker-healthcheck），配置模板与 systemd 单元模板移入
  `share/templates/`，版本清单移入 `share/`。

### 变更

- Linux 下 `frampp status` / 控制面板显示的服务名改为 **`mysql`**
  （`modules/mysql`、数据目录 `var/mysql`、日志 `mysql.log` /
  `mysql.err.log`）；Windows 本轮保持 `mariadb`，后续里程碑对等切换。
- Linux 运行时依赖基线：MySQL 模块要求 glibc ≥ 2.17（兼容 CentOS 7）与
  `libaio`；Docker 镜像安装 `libaio1` / `libnuma1`。
- Agent 的 MySQL 工具优先读取 `mysql_readonly_password`，兼容回读旧的
  `mariadb_readonly_password`；日志工具同时接受 `mysql` 与 `mariadb`。
- CI 冒烟测试断言 MySQL GLIBC ≤ 2.17，并通过 PHP PDO（与控制面板同链路）
  验证数据库连接。
- FRAMPP 版本号提升至 `0.7.0`。

### 说明

- MySQL 8.0 已于 2026-04-30 EOL（8.0.46 为最终版），作为 CentOS 7 兼容基线
  采用；面向现代发行版的 MySQL 8.4 LTS / MariaDB 11.4 双变体切换已列入后续
  计划。
- **MariaDB 数据目录与 MySQL 8.0 不兼容**。从 0.6.0 升级需重建数据库
  （见 `docs/user/upgrade.md`）。
- FRAMPP 创建的数据库账号使用 `mysql_native_password`，保证 localhost TCP
  下 PHP mysqlnd / Adminer / CLI 等客户端的广泛兼容（MySQL 8.0 仍支持；
  8.4 默认禁用，相关于后续双变体切换）。

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
