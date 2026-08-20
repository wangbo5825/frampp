# FRAMPP 项目蓝图

> 状态：设计稿 v1.4（2026-08-20，M1 组件定版 + Linux x86_64 变体定版 + 0.3.0 组件精简决策）
> 用途：独立 Codex 项目启动时的实施依据
> 前置调研：已完成（组件选型、命名、Agent/MCP 定位、生态现状）

---

## 1. 项目定位

一句话：FRAMPP 是一个面向现代 PHP 开发者的“一键安装、开箱即用”的运行环境与开发平台，延续 LAMPP / XAMPP / NMPP 的命名与产品形态，但底座换成 FrankenPHP，并把 **AI Agent 接入（MCP）作为一级组件**。

- 目标用户：PHP 开发者（本地开发）、小团队（内网部署 / 演示）、开源社区
- 平台：**Windows 优先**（与 XAMPP 一致的形态），Linux / macOS / Docker 变体为后续里程碑
- 差异化定位：不是“又一个 PHP 环境”，而是 **AI 时代的 PHP 运行环境**——自带 Agent（MCP 服务器），把 MySQL / Redis / 日志 / 项目环境开放给主流 AI 编码工具

---

## 2. 命名与谱系

### 2.1 字母含义

| 字母 | 组件 | 角色 |
| --- | --- | --- |
| F | FrankenPHP | 应用服务器（内置 Caddy、自动 HTTPS、worker 模式） |
| R | Redis | 分布式缓存 / 队列 / 会话 |
| A | Agent | MCP 服务器：对接 AI Agent 的工具接入层 |
| M | MySQL / MariaDB | 关系数据库（默认发行 MariaDB，字母含义不变） |
| P | PHP | 主要开发语言 |
| P | Python | 支撑语言：自动化 / AI 负载（可选组件） |

### 2.2 谱系

`LAMPP(Linux+Apache+MySQL+PHP+Perl)` → `XAMPP(X+Apache+MySQL+PHP+Perl)` → `NMPP(Nginx+MySQL+PHP+Perl)` → **`FRAMPP(FrankenPHP+Redis+Agent+MySQL+PHP+Python)`**

### 2.3 决策记录（不重复调研）

- **A 的候选评估**：APCu（进程内缓存）、Adminer（数据库管理）、Authelia（SSO/2FA）、Apache APISIX（API 网关）。
  - 结论：**A = Agent**。理由：差异化最大（同类产品无此形态）、生态时机成熟（MCP 已成事实标准）、与开源贡献目标契合。
  - APCu 不占字母，作为**内置扩展**默认附带（L1 本地缓存，与 Redis 组成两级缓存）。
  - Adminer 作为附赠开发工具（不占字母）。
  - Authelia 否决 / 移除：SSO / 2FA 属具体应用开发范畴，不作为平台组件（v1.1 定版）。
  - Apache APISIX 否决：与 FrankenPHP 内置 Caddy 职责重叠，依赖 etcd/OpenResty，过重。
- **最后一个 P**：Perl → Python。
  - 理由：Perl 在现代 PHP 开发中已无实际场景（XAMPP 中属历史包袱）；Laragon 等现代 Windows PHP 环境已用 Python 取代 Perl；Python 与 Redis / MySQL / AI 生态协同更好。
- **名称可用性**：未检索到同名知名项目，可放心使用。

### 2.4 M1 组件定版（v1.1）

- **M = MariaDB（默认）**：再分发许可更宽松、与 XAMPP 先例一致、Windows 原生支持成熟；MySQL 保留为可选。字母含义不变。
- **R = Redis（Windows 直接用 Redis）**：官方无原生 Windows 构建（官方文档推荐 Memurai / WSL）。采用社区活跃维护的 `redis-windows` 构建（随官方源码同步发布、含安全修复），固定版本 + SHA-256 校验 + 仅绑定 127.0.0.1 + 随机密码。风险中低、可接受并文档化；若维护滞后则切换 Memurai（Redis 官方 Windows 合作伙伴）。
- **P = PHP 由 FrankenPHP 提供（CLI 模式）**：不单独安装 PHP；Web 用 `frankenphp php-server`，命令行用 `frankenphp php-cli`。FrankenPHP v1.12+ 原生支持 Windows（链接官方 Visual Studio 编译的 PHP 二进制，扩展齐全）。
- **Composer 随包集成**：以 `composer.phar` 分发，由 `frankenphp php-cli composer.phar` 执行；M1 需验证 mbstring / openssl / xml 等 Composer 依赖扩展可用。
- **APCu / Adminer 保留**：均为轻量附赠（APCu 扩展 DLL、Adminer 单文件），不占字母，保留在默认发行中。
- **Python 保留为嵌入式轻量方案**：默认勾选的可选组件，用 uv / 嵌入式发行版按需安装，控制包体积。

### 2.5 发布模型决策（v1.2，2026-08-20）

- **产品定位**：只解决普通用户"一键安装、开箱即用"问题，**不提供**高级用户的多 PHP 版本并存（Laragon / Herd 式切换）。
- **发布形态**：类似 XAMPP——按 **FRAMPP 版本 × 组件通道 × 环境** 发布不同的一键安装包：`frampp-setup-<channel>-<version>-<env>.exe`。
- **通道**：当前仅 `8.5`（FrankenPHP 1.12.7 / PHP 8.5.9 / MariaDB 12.3.2 / Redis 8.10.1）；新增通道需 FrankenPHP 提供对应 Windows 构建并在 `channels.json` / `versions-<channel>.json` 注册。
- **发布管线**：`installer/scripts/release.ps1` 构建各通道、生成 SHA256SUMS、可选直发 GitHub Releases（tag `v<version>`）。流程见 [docs/releases.md](releases.md)。

### 2.6 Linux x86_64 变体决策（v1.3，2026-08-20）

- **目标**：与 XAMPP Linux 形态一致的**自包含一键安装包**，避开系统包管理器依赖；本机无 Linux 时由 CI（ubuntu）构建与冒烟验证。
- **发布形态**：`frampp-setup-<channel>-<version>-linux-x86_64.run`（XAMPP 风格单文件自解压安装器；内部载荷为暂存目录内容的 tar.gz，运行时自动校验、解压到目标目录并执行 `./install.sh` 就地初始化与启动；目录可整体移动，卸载用 `./uninstall.sh`）。
- **组件矩阵（环境级版本清单 `installer/config/versions-linux-x86_64.json`）**：
  - **FrankenPHP**：官方静态构建 `frankenphp-linux-x86_64`（musl，无 glibc 依赖）；官方默认扩展集**内置 APCu / redis / mysqli / pdo_mysql / mbstring / openssl / xml / zip / intl** 等，Linux 无需单独 APCu 扩展。
  - **MariaDB**：官方 bintar `mariadb-12.3.2-linux-systemd-x86_64.tar.gz`（自包含目录树；安装/运行均加 `--no-defaults` 隔离系统 `/etc/my.cnf`）。
  - **Redis**：**官方源码 8.10.1 静态编译**（首选 Alpine musl 静态，Docker 不可用时回退宿主编译），保证与 Windows 版本一致、品牌一致且无 glibc 依赖；不用 Valkey 预编译包（品牌不一致且将 glibc 基线抬到 2.35）。
  - Composer / Adminer：与 Windows 同一文件（跨平台 phar/php），复用同一缓存。
- **运行模型**：php.ini 由 `php.ini.linux.template` 生成（静态扩展无 `extension=` 指令）；CLI 与服务器统一通过 `bin/frampp` 包装器启动（`frankenphp php-cli -c <php.ini>` + `PHPRC` 环境变量），控制面板 `ServiceManager` 已跨平台（`kill`/`/dev/null`、去 `.exe`）。
- **安全基线不变**：127.0.0.1 绑定、随机密码、只读账号 `frampp_ro`、审计日志。

### 2.7 0.3.0 组件精简决策（v1.4，2026-08-20）

面向 0.3.0 的 Linux x86_64 安装包瘦身（目标：安装包体积显著下降，功能不变）：

- **MariaDB 精简（目标 30~50 MB）**：由官方 bintar 改为**源码编译**（`installer/scripts/linux/build-mariadb.sh`）：
  - CMake Release + `BUILD_CONFIG=mysql_release`；禁用 PHP 场景几乎不用的插件：RocksDB / Mroonga / Connect / Spider / Sphinx / S3 / OQGraph / TokuDB / Feedback / Archive / Blackhole / Example。
  - 对 `bin/` 与 `lib/plugin/` 全部可执行文件执行 `strip --strip-unneeded`。
  - 删除 `mysql-test/`、`sql-bench/`、`man/`、`include/`、`lib/*.a` 及开发工具（`mysql_config` 等）。
  - 保留 `mariadbd`/`mysqld`、`mysql`/`mariadb`、`mysqladmin`、`mysqldump`、`mariadb-install-db` 等核心工具与 `share/`（errmsg/charset 运行时必需）。
  - 取舍：仍依赖系统 glibc 与 OpenSSL（与 bintar 基线一致），换取体积大幅下降。
- **FrankenPHP 定制构建**（`installer/scripts/linux/build-frankenphp.sh`，基于官方 `build-static.sh` + static-php-cli / spc）：
  - PHP 扩展：官方默认集去掉 **intl / soap / gmp / bcmath / exif / imagick**（xdebug 不在默认集，天然不包含）；保留 APCu / redis / mysqli / mbstring / openssl / xml 等核心扩展。
  - Caddy 模块：去掉 **Mercure / Vulcain**，加入 **Souin**（HTTP 缓存，锁定兼容 commit `65cb2411…`）与 `caddy-cbrotli`。
  - `SPC_LIBC=glibc`：glibc mostly static（除 libc 外静态链接），兼容主流发行版。
  - `COMPRESS=1`：UPX 压缩最终二进制；Go 链接器 `-w -s` 去符号（spc 默认）。
  - 风险：源码构建耗时显著增长（CI 单作业约 1.5~2 h）；UPX 可能触发杀软误报（文档提示）。
- **Python 3.13 内置（精简）**：采用 `python-build-standalone` 的 `install_only_stripped` 构建（自包含、去头文件/测试/符号），二次删除 `test/ tkinter/ idlelib/ turtledemo/ __pycache__`，保留 pip/ensurepip；目标体积约 30 MB。`bin/frampp` 包装器自动把 `python/bin` 加入 PATH，`runtime.json` 记录版本。
- **影响面**：仅 Linux x86_64 变体（0.3.0）；Windows 变体保持官方预编译组件，后续里程碑再做对等精简。

---

## 3. 总体架构

### 3.1 组件拓扑

```mermaid
flowchart LR
  subgraph FRAMPP[FRAMPP 一键安装包]
    FP[FrankenPHP<br/>内置 Caddy + worker 模式]
    MARIA[(MariaDB)]
    REDIS[(Redis)]
    APCU[APCu 扩展<br/>L1 本地缓存]
    AGENT[Agent / MCP 服务器]
    PY[Python 运行时<br/>可选]
    ADMIN[Adminer<br/>附赠]
    PANEL[控制面板]
  end
  DEV[AI 编码 Agent<br/>Claude Code / Cursor / Codex]
  DEV -- "MCP stdio / Streamable HTTP" --> AGENT
  AGENT --> MARIA
  AGENT --> REDIS
  AGENT --> FP
  FP --> MARIA
  FP --> REDIS
  FP --> APCU
  PANEL --> FP
  PANEL --> MARIA
  PANEL --> REDIS
```

### 3.2 缓存分层

- **L1**：APCu（进程内用户缓存；worker 模式下跨 worker 线程共享，需 `apc.enable_cli=1`）
- **L2**：Redis（跨进程 / 跨节点共享、队列、会话）
- 原则：热数据走 L1，共享状态 / 队列一律走 L2
- 注意：水平扩展时 APCu 按进程隔离，多实例共享必须用 Redis

### 3.3 运行模型要点

- FrankenPHP 采用 ZTS 线程模型，worker 模式为默认（Symfony 7.4+ / API Platform 官方支持）
- 官方基准：API Platform 应用在 worker 模式下比 FPM 快约 3.5 倍
- 自动 HTTPS：本地证书 + hosts 管理
- PHP 运行时由 FrankenPHP 自带：Web 与命令行均走 CLI 模式（`php-server` / `php-cli`），不单独安装 PHP；内置 Composer（`php-cli composer.phar`）供项目模板与 Agent 使用

---

## 4. 仓库结构（独立目录 `frampp/`）

```text
frampp/
├─ README.md / LICENSE / CONTRIBUTING.md
├─ docs/                  # 架构、安全、用户手册
├─ src/
│  ├─ php/                # PHP 组件源码（MCP server、控制面板后端）
│  └─ python/             # Python 辅助组件
├─ agent/                 # Agent / MCP 服务器（独立可复用包）
├─ control-panel/         # 控制面板（GUI / CLI）
├─ installer/             # 安装器脚本与打包配置
├─ templates/             # 项目模板：API Platform starter、PHP 最小工程
├─ dist/                  # 第三方二进制（FrankenPHP / MariaDB / Redis / Python）
├─ tests/                 # 单元 / 集成 / 端到端
└─ .github/workflows/     # CI（多平台矩阵）
```

### 4.1 安装后布局（仿 XAMPP）

```text
frampp/
├─ frankenphp/            # 应用服务器 + PHP
├─ mariadb/               # 数据库（MariaDB）
├─ redis/                 # 缓存 / 队列
├─ python/                # Python 运行时（可选）
├─ agent/                 # MCP 服务器
├─ bin/                   # 内置 CLI 工具（composer.phar 等）
├─ htdocs/                # 默认站点目录
├─ logs/                  # 统一日志
├─ data/                  # 数据与配置
└─ FRAMPP Control Panel.exe
```

---

## 5. Agent（MCP 服务器）设计

### 5.1 定位

FRAMPP 的“AI 接入层”：把本地环境能力封装成 MCP 工具，供主流 AI 编码工具调用。

### 5.2 协议

- v1：**MCP（Model Context Protocol）**，stdio + Streamable HTTP 两种 transport
- 路线图：**A2A（Agent2Agent，Linux Foundation / Google 主导）** 作为 2.0
- MCP 已是事实标准：Claude Code、Cursor、Codex、Cline、Copilot、Windsurf 等均支持

### 5.3 工具清单（v0.1）

| 工具 | 说明 | 安全约束 |
| --- | --- | --- |
| `mysql.list_tables` | 列出数据库表 | 只读 |
| `mysql.describe` | 查看表结构 | 只读 |
| `mysql.query` | 执行查询 | 只读账号 + 强制 LIMIT |
| `redis.keys` | 扫描 key（SCAN） | 只读 |
| `redis.get` / `redis.ttl` | 读取值与过期时间 | 只读 |
| `redis.info` | 内存 / 统计信息 | 只读 |
| `logs.tail` | 实时跟踪应用日志 | 路径白名单 |
| `logs.search` | 按关键字过滤日志 | 路径白名单 |
| `env.php_version` / `env.composer_show` | 环境信息 | 只读命令 |
| `env.services_status` | 服务启停状态 | 只读 |
| `env.project_info` | 项目结构 / composer.json | 只读 |

### 5.4 实现选型

- 首选 **PHP**（`php-mcp`，PHP 基金会合作维护），保持“PHP 为主”的定位
- 备选 **Python**（官方 MCP SDK）；若 Agent 采用 Python 实现，则“最后一个 P = Python”的叙事更强——二选一时记录取舍，不混用
- 框架无关：`php-mcp/server` 支持属性注解式声明工具，便于后续扩展
- **M2 决策（2026-08-19）**：v0.1 采用**零外部依赖**的 PHP 实现（自研 MCP stdio 传输层 + RESP 只读客户端 + 工具 `#[AsTool]` 注解）；协议兼容 MCP（initialize / tools/list / tools/call），工具注解风格与 php-mcp 对齐，后续可平滑迁移官方 SDK；理由：本地开发工具包体小、无供应链风险、在受限网络下可完整测试

### 5.5 安全边界（必须项）

- 默认仅绑定 `127.0.0.1`
- MariaDB 独立只读账号（仅 SELECT 权限，自动加 LIMIT）
- Redis 命令白名单（只读命令）
- 外部命令白名单（`php -v`、`composer show` 等只读命令）
- 全部工具调用写审计日志（缓冲到 Redis，落盘）
- 默认关闭或按项目 opt-in 开启

### 5.6 客户端接入示例

```json
{
  "mcpServers": {
    "frampp": {
      "command": "php",
      "args": ["agent/bin/frampp-mcp", "--project", "my-app"]
    }
  }
}
```

---

## 6. 关键实现要点

### 6.1 FrankenPHP

- worker 模式为默认运行方式
- PHP 由 FrankenPHP 自带，默认 CLI 模式：`frankenphp php-server`（Web）、`frankenphp php-cli`（命令行）；Composer 以 `php-cli composer.phar` 方式集成
- 原生 Windows 支持自 v1.12 起（链接官方 Visual Studio 编译的 PHP 二进制，扩展齐全）；M1 锁定版本并校验哈希
- APCu 扩展默认启用；worker 模式需 `apc.enable_cli=1`（官方镜像默认不带，是最易踩的坑）
- `apc.shm_size` 默认预设 128M，控制面板可调
- 自动 HTTPS（本地证书 + hosts 管理）：**暂缓（2026-08-20 决策）**——仅测试用途、对用户无实际价值；若后续测试必需再启用

### 6.2 MariaDB / Redis

- 数据库默认 **MariaDB**（M 字母含义不变）；首次安装生成随机强密码，控制面板可查看 / 重置
- Redis 采用社区 `redis-windows` 构建（随官方源码同步），固定版本 + SHA-256 校验，默认仅绑定 127.0.0.1 + 随机密码；备选 Memurai（Redis 官方 Windows 合作伙伴）
- 端口冲突检测（3306 / 6379 / 443 等）
- Redis 用途：缓存、队列、会话、Agent 审计日志缓冲

### 6.3 Python

- 可选组件，默认勾选
- 用 uv / 嵌入式发行版按需安装，控制包体积
- 用途：AI 负载、数据脚本、Agent 的 Python 实现备选

### 6.4 模板与生态

- **API Platform starter**：与 FrankenPHP 同作者（Kévin Dunglas），官方 demo 即 Symfony + API Platform；v4.x 提供 Symfony / Laravel 适配。示例项目预配 worker 模式 + MariaDB + Redis，装完即可演示完整 API（Swagger + Admin + 自动文档）
- 项目模板创建通过内置 Composer 完成（`frankenphp php-cli composer.phar create-project ...`）
- Adminer：单文件数据库管理，由 FrankenPHP 直接提供

---

## 7. 安全与质量基线

- 默认安全：随机密码、localhost 绑定、最小权限、审计日志
- 测试：单元测试（PHPUnit / Pest）、组件集成测试、安装器全流程测试（Windows VM）、CI（GitHub Actions）
- 发布：GitHub Releases；代码签名列为里程碑（成本项）
- 供应链：第三方二进制哈希校验（含 MariaDB、Redis Windows 构建、composer.phar、扩展 DLL）
- 许可证：项目本体 MIT；**注意第三方二进制再分发条款**（已定：默认 MariaDB，再分发条款宽松，XAMPP 已改用 MariaDB 为先例；MySQL 仅作可选）

---

## 8. 里程碑

| 里程碑 | 内容 | 完成标准 |
| --- | --- | --- |
| M0 仓库落地 | 独立目录 + GitHub 仓库、README、LICENSE、CI 骨架、蓝图入库 | 可 clone、可提交 |
| M1 核心运行时 | FrankenPHP + MariaDB + Redis + APCu 打包；控制面板 MVP（启停 / 状态 / 端口 / 日志） | 安装后一键启动三件套（2026-08-19 已实现并本地验证：download.ps1 / init.ps1 / 控制面板 CLI + Web） |
| M2 Agent v0.1 | MCP 服务器 + MariaDB / Redis / 日志 / 环境工具 + 安全边界 | Claude Code / Cursor 可调用工具 |
| M3 开发体验 | Adminer、本地域名 / HTTPS、API Platform starter、项目一键创建 | ✅ 2026-08-20 完成并验证：Adminer 随包安装；`frampp new-project`（minimal 离线模板 / symfony / api-platform = symfony/skeleton + api-platform/core），api-demo 实测 `/api` 返回 Entrypoint JSON-LD；本地域名 / HTTPS 暂缓（仅测试用途、无用户价值，必要时再加） |
| M4 生产模式 | 安装器 / 升级流程、代码签名、多用户文档（Authelia 已移除：属应用开发范畴） | 可对外正式发布（2026-08-20 已实现：Inno Setup 安装器 + 自动初始化/自启 + 卸载清理 + 升级文档；代码签名待证书采购，属成本项） |
| M5 生态 | A2A 路线图、Linux / macOS / Docker 变体、社区贡献指南 | ✅ Linux x86_64 变体已实现（2026-08-20：版本清单 / init.sh / install.sh / build-linux-package.ps1 / CI 冒烟）；macOS / Docker 变体待做 |

---

## 9. 风险与开放问题

- **PHP MCP SDK 生态年轻**：命名与“官方”归属有变动，选定后锁定维护活跃的版本
- **已定：默认 MariaDB**（再分发许可宽松），MySQL 仅作可选
- **Windows 原生 Redis**：官方无原生构建，采用社区 `redis-windows` 发行（固定版本 + 哈希校验 + localhost + 随机密码），风险中低；若维护滞后切换 Memurai。Valkey 官方暂无 Windows 支持；Linux 变体采用**官方 Redis 源码静态编译**（版本与 Windows 一致），不引入 Valkey
- **FrankenPHP Windows 构建扩展可用性**：M1 需验证官方 Windows 构建含 Composer 所需扩展（mbstring / openssl / xml）及 APCu
- **包体积**：Python 与安装器体积控制，采用可选组件 + 按需下载
- **代码签名**：Windows SmartScreen 信任成本，列为 M4
- **Agent 安全边界**：工具调用权限是社区信任的关键，优先实现并文档化

---

## 10. 下一步

1. ✅ 在独立目录创建 Codex 项目，把本蓝图作为 `docs/blueprint.md` 入库
2. ✅ M0：`git init`、README / LICENSE / CI 骨架、GitHub 仓库（wangbo5825/frampp）
3. ✅ M1：FrankenPHP + MariaDB + Redis + APCu 打包（download.ps1 / init.ps1）+ 控制面板 MVP（启停 / 状态 / 端口 / 日志），本机端到端验证通过
4. 下一步：**M2 Agent v0.1**——MCP 服务器 + MariaDB / Redis / 日志 / 环境工具 + 安全边界
