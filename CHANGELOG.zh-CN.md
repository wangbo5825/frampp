# 变更日志

FRAMPP 的重要变更记录。

## [0.8.3] - 2026-10-22

面向 Windows、Linux x86_64/aarch64 和 Docker 的紧急安全更新。

### 安全

- 内置运行时升级到 **PHP 8.5.12**，修复 CVE-2026-109618（OOM 状态破坏）
  与 CVE-2026-109619（陈旧全局请求状态）。二者均为可导致未认证远程代码执行
  的严重漏洞；PHP 官方说明升级是唯一完整修复方式。
- FrankenPHP 从 1.12.7 升级到 **1.13.2**，修复 4 个 FrankenPHP 自身安全
  问题：嵌入式应用临时目录抢占、断连请求占用 PHP 线程、循环数组导致进程
  崩溃，以及 worker 错误状态跨请求泄漏。
- Linux 定制构建迁移到 static-php-cli v3（`LIBC` / `XCADDY_ARGS` /
  `spc craft`），继续保持完全静态 musl 产物，并锁定 Souin、
  caddy-access-filter 和 pogo_scheduler 模块。
- UPX 压缩改为显式 opt-in（`FRAMPP_COMPRESS=1`）：原架构相关 UPX 在原生
  aarch64 runner 上无法执行；关闭后包体略大，但两架构构建更可重复、可验证。

### 变更

- Windows、Linux x86_64/aarch64 与多架构 Docker 镜像统一切换到
  PHP 8.5.12 + FrankenPHP 1.13.2 安全基线。
- 组件清单显式记录 `phpVersion=8.5.12`；Linux 冒烟测试断言 PHP 8.5.12
  且 FrankenPHP 不低于 1.13.2。
- Windows 升级解压新版本前会清理旧 FrankenPHP 模块目录，避免遗留旧二进制。
- 组件下载器发现缓存哈希不匹配时会先删除旧文件再重新下载，避免断点续传
  把旧 ZIP 与新数据拼接。

## [0.8.2] - 2026-10-21

Linux-only 临时预发布版本（不提供 Windows 安装包）。

### 新增

- Linux 定制 FrankenPHP 构建集成 **pogo_scheduler v0.1.0**
  （`github.com/wangbo5825/scheduler/module@e492454`，即 tag `v0.1.0` 对应
  commit；Go 模块位于 `module/` 子目录，故按 commit 固定）。可在
  `etc/scheduler.caddy` 中选择 HTTP 任务（推荐，走 PHP worker 请求链路）或
  外部命令任务，支持 interval / cron 定时与 overlap 控制；调度事件写入
  FrankenPHP 日志。
- 新的应用目录布局 `apps/<app>/{htdocs,config,src,var}`：只有
  `apps/<app>/htdocs` 对外提供。默认站点使用 `apps/default/htdocs`；
  `frampp new-project` 与控制面板站点管理的默认目录也使用该布局。init 会
  迁移旧 `htdocs/`（裸机安装保留 `htdocs -> apps/default/htdocs` 符号链接；
  Docker 保留旧卷并把内容复制到新的 `apps` 卷）。

### 变更

- 安装器与初始化提示改为英文优先、中文第二语言；Windows Inno Setup 的
  状态提示通过 `[CustomMessages]` 跟随安装器语言。

## [0.8.1] - 2026-10-11

## [0.8.1] - 2026-10-11

### 新增

- **arm64（aarch64）Linux 支持**：新增 `linux-aarch64` 目标与独立组件矩阵
  （`installer/config/versions-linux-aarch64.json`），发布
  `frampp-<version>-linux-aarch64.run`。FrankenPHP（musl 完全静态）与 Redis
  在 arm64 上原生构建；MySQL 8.0 使用官方 `linux-glibc2.28-aarch64` 通用包
  并按同一脚本裁剪（官方无 arm64 minimal 变体，故基线为 glibc 2.28）；
  Python 使用对应架构的 python-build-standalone 运行时。
- 多架构 Docker 镜像：CI 分别构建并推送 `linux/amd64` 与 `linux/arm64`，
  再为版本 tag 与 `latest` 发布 manifest list。
- FrankenPHP 定制构建的 xcaddy 模块全部锁定版本（`caddy-cbrotli@v1.0.1`、
  `storages/otter/caddy@v0.0.20`、Souin 按 commit、`caddy-access-filter@v1.2.1`），
  两个架构构建出的 Caddy 版本一致（v2.11.7），不再随模块代理解析结果漂移。
- 新增共用冒烟脚本 `installer/scripts/linux/smoke-test.sh`，x86_64 与 aarch64
  CI 作业共用。

### 修复

- `frampp restart` 偶发启动失败：`stop()` 强杀进程树后立即返回，导致启动前的
  端口预检把尚未退出的旧进程判为“端口被占用”。现在 `stop()` 会等待进程退出与
  端口 / socket 释放，预检也会短暂重试后再报冲突。

### 变更

- FRAMPP 版本号提升至 `0.8.1`。

## [0.8.0] - 2026-09-06

### 新增

- 集成 **caddy-panel**（git 子模块固定引用）作为 Caddy Web 管理界面，入口
  `http://127.0.0.1:8081/panel`：管理站点、Caddyfile、证书与日志，支持
  `/adapt` 校验、热重载、快照与 last-good 恢复。init 预置模块
  （`modules/caddy-panel`）、生成 `config.php` / `panel.bootstrap.php`
  （`APP_ROOT`、`PANEL_BASE=/panel/`）并无交互创建管理员；8081 根路径继续
  提供平台控制台（服务 / IP 访问控制）。
- 新增 `frampp restart [service]` 指令（默认 `all`；按依赖反序停止、正序启动）。
- 启动加固：`frampp start` 启动前预检端口 / unix socket 占用，启动后最多等待
  10 秒就绪；失败返回 `started=false` 并附日志末行、退出码非零。

### 变更

- 安装包布局：文档与 README（英文 + 中文）统一放入 `share/docs/`；版本文件位于
  `etc/VERSION`（`frampp version` 保留旧根路径回退）。
- Caddyfile 改为 `etc/global.caddy` + `import etc/caddy.d/*.caddy` 组装
  （与 caddy-panel 管理结构一致），8081 控制台以 `handle_path` 提供 `/panel`。
- FRAMPP 版本号提升至 `0.8.0`。

## [0.8.0] - 2026-09-06

### 新增

- 集成 **caddy-panel**（git 子模块固定引用）作为 Caddy Web 管理界面，入口
  `http://127.0.0.1:8081/panel`：管理站点、Caddyfile、证书与日志，支持
  `/adapt` 校验、热重载、快照与 last-good 恢复。init 预置模块
  （`modules/caddy-panel`）、生成 `config.php` / `panel.bootstrap.php`
  （`APP_ROOT`、`PANEL_BASE=/panel/`）并无交互创建管理员；8081 根路径继续
  提供平台控制台（服务 / IP 访问控制）。
- 新增 `frampp restart [service]` 指令（默认 `all`；按依赖反序停止、正序启动）。
- 启动加固：`frampp start` 启动前预检端口 / unix socket 占用，启动后最多等待
  10 秒就绪；失败返回 `started=false` 并附日志末行、退出码非零。

### 变更

- 安装包布局：文档与 README（英文 + 中文）统一放入 `share/docs/`；版本文件位于
  `etc/VERSION`（`frampp version` 保留旧根路径回退）。
- Caddyfile 改为 `etc/global.caddy` + `import etc/caddy.d/*.caddy` 组装
  （与 caddy-panel 管理结构一致），8081 控制台以 `handle_path` 提供 `/panel`。
- FRAMPP 版本号提升至 `0.8.0`。

## [0.7.2] - 2026-09-01

### 修复

- Linux FrankenPHP 定制构建中锁定的 `caddy-access-filter` 由 v1.2.0 升级到
  **v1.2.1**（IP 访问过滤模块的错误修正版本）；同步修正构建缓存标记与脚本
  注释中残留的 v1.2.0 引用，避免缓存的 FrankenPHP 构建在错误模块版本下被复用。

### 变更

- FRAMPP 版本号提升至 `0.7.2`。

## [0.7.1] - 2026-09-01

### 新增

- Linux 安装根目录新增 LAMPP 风格总控命令：`frampp` 为指向 `bin/frampp` 的
  符号链接，安装后可直接在安装目录执行 `./frampp start|stop|status`。
  链接在打包阶段创建（`installer/scripts/build-linux-package.ps1`），
  `init.sh` 在缺失时自动兜底重建（如手工复制目录的场景）。

### 变更

- FRAMPP 版本号提升至 `0.7.1`。

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
