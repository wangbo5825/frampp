# FRAMPP 版本发布 / FRAMPP Releases

## 发布模型 / Release Model

产品定位：**面向普通用户的一键安装**（类似 XAMPP），按 **FRAMPP 版本 × 组件通道 × 环境** 发布不同的一键安装包；**不提供**高级用户的多 PHP 版本并存（Laragon / Herd 式）。

Positioning: **one-click installers for everyday users** (XAMPP-style), published per **FRAMPP version × component channel × environment**; we do **not** provide multi-PHP coexistence for power users (Laragon / Herd style).

命名规则 / Naming（v0.7.0 起简化，通道并入 Release note）:

```text
frampp-<version>-<env>.<ext>
示例 / e.g. frampp-0.7.0-windows-x64.exe
示例 / e.g. frampp-0.7.0-linux-x86_64.run
```

- `<channel>`：组件通道 / component channel（当前 / current `8.5` = FrankenPHP 1.12.7 / PHP 8.5.9 / MySQL 8.0.46（Linux）/ Redis 8.10.1；Windows 数据库仍为 MariaDB 12.3.2）
- `<version>`：FRAMPP 版本号（语义化，随 Release 递增，来源：仓库 `VERSION` 文件）/ semantic version, bumped per release (from repo `VERSION`)
- `<env>`：目标环境 / target environment（`windows-x64` / `linux-x86_64`；macOS 属后续里程碑，Docker 以 `ghcr.io/wangbo5825/frampp:<version>` 镜像发布）
- `<ext>`：`.exe`（Windows，Inno Setup）或 `.run`（Linux，自解压单文件安装器 / self-extracting single-file installer）

> **v0.7.0 起实施 / Implemented since v0.7.0**：FRAMPP 与 PHP 大版本保持一致
> （当前通道 `8.5`），安装包命名简化为 `frampp-<version>-<env>.<ext>`，
> 版本与 PHP / 组件的对应关系保留在 Release note 中；运行时使用的
> `installer/` 内容已迁出——脚本移入 `bin/`，模板移入 `share/templates/`，
> 安装包内不再包含 `installer/` 目录。

> **v0.7.1 起实施 / Implemented since v0.7.1**：Linux 安装根目录新增 LAMPP
> 风格总控命令 `frampp`（符号链接 → `bin/frampp`），安装后可直接
> `./frampp start|stop|status`。

> Release Note 语言规范 / Language convention for release notes：正文采用
> **先英文、后中文** 的两段式结构（English section first, then Chinese）。

## 发布步骤 / Release Steps

```powershell
# 1. Windows 安装包（在 Windows 上执行，需要 Inno Setup 便携版自动下载）
#    Windows installer (run on Windows; Inno Setup portable is auto-downloaded)
powershell -ExecutionPolicy Bypass -File installer/scripts/release.ps1 -Env windows-x64

# 2. Linux 安装包（在 Linux + pwsh 7 上执行；Redis 由官方源码静态编译，需 Docker 或 gcc）
#    Linux .run (run on Linux + pwsh 7; Redis is statically compiled from source, needs Docker or gcc)
pwsh -File installer/scripts/release.ps1 -Env linux-x86_64

# 3. 发布到 GitHub Releases（自动创建 tag v<version> 并上传安装包与哈希清单）
#    Publish to GitHub Releases (creates tag v<version>, uploads installers + hashes)
powershell -ExecutionPolicy Bypass -File installer/scripts/release.ps1 -Env windows-x64 -Publish
pwsh -File installer/scripts/release.ps1 -Env linux-x86_64 -Publish
```

CI 替代方案：推送 `v*` tag 时，Linux 包构建完成后自动上传到同名 Release，
`docker` 作业还会构建并推送 Docker 镜像；也可在 workflow_dispatch 时传入
`release_tag` 手动上传（`gh workflow run ci.yml -f release_tag=v0.7.1`）。
CI alternative: pushing a `v*` tag builds the Linux package and uploads it to
the release with the same name; the `docker` job also builds and pushes the
Docker image. You can also pass `release_tag` on workflow_dispatch to upload
manually (`gh workflow run ci.yml -f release_tag=v0.7.1`).

## Docker 镜像 / Docker Image

Linux `.run` 构建完成后，镜像复用该产物，单镜像包含完整 FRAMPP 技术栈：

```bash
docker run -d --name frampp \
  -p 8080:8080 -p 8081:8081 \
  -v frampp-data:/opt/frampp/var \
  -v frampp-logs:/opt/frampp/logs \
  -v frampp-htdocs:/opt/frampp/htdocs \
  ghcr.io/wangbo5825/frampp:0.7.0
```

发布到 GitHub Container Registry：

```powershell
pwsh -File installer/scripts/build-linux-package.ps1 -Env linux-x86_64
pwsh -File installer/scripts/build-docker.ps1 -Registry ghcr.io/wangbo5825 -ImageName frampp -Push
```

更多卷、端口与源码构建说明见 [docs/user/docker.md](docs/user/docker.md)。

## Publish to Gitee / 发布到 Gitee

GitHub is the single source of truth. The repository is mirrored to Gitee automatically by the **GitHub Actions workflow** `.github/workflows/mirror-gitee.yml` (on every push to `main`, branches and tags are pushed to Gitee), so **do not push to Gitee manually**. The workflow requires the repository secret `GITEE_TOKEN` (Gitee personal access token, scope: `projects`).

> Note: if you previously enabled Gitee's built-in GitHub mirror sync (管理 → 仓库设置 → 镜像仓库管理), disable it to avoid two-way sync conflicts — the GitHub workflow is now the single sync path.

Gitee mirror sync does **not** copy GitHub Releases, so a Gitee 发行版 (with installer attachments) is optional. If you also publish Gitee releases, use the publish script (requires pwsh 7 and a Gitee token with `projects` scope):

```powershell
pwsh -File installer/scripts/publish-gitee.ps1 -Token $env:GITEE_TOKEN -Tag v0.7.0 `
  -NotesFile .tmp-notes.md -Assets dist/installer/frampp-0.7.0-windows-x64.exe,dist/installer/SHA256SUMS.txt
```

Notes:

- Push only to GitHub (`git push`); the `Mirror to Gitee` workflow pushes the update to Gitee automatically.
- Gitee attachment limit is **100 MB per file**; the Linux `.run` installer (over 100 MB) stays GitHub-only.
- The script is idempotent: it creates the release when missing and uploads assets without duplicating them.

GitHub 是唯一推送源。仓库由 **GitHub Actions 工作流** `.github/workflows/mirror-gitee.yml` 自动镜像到 Gitee（每次 push 到 `main` 时，分支与标签自动推送到 Gitee），**无需再手动推送到 Gitee**。工作流需要仓库级 secret `GITEE_TOKEN`（Gitee 私人令牌，权限含 `projects`）。

> 注意：如之前在 Gitee 侧开启了内置 GitHub 镜像同步（管理 → 仓库设置 → 镜像仓库管理），请停用以避免双向同步冲突——现在由 GitHub 工作流作为唯一同步通道。

镜像同步**不会**复制 GitHub Releases，因此 Gitee 发行版（含安装包附件）为可选项。如仍需发布 Gitee 发行版，运行发布脚本（需要 pwsh 7 与 Gitee 私人令牌，权限含 `projects`）：

```powershell
pwsh -File installer/scripts/publish-gitee.ps1 -Token $env:GITEE_TOKEN -Tag v0.7.0 `
  -NotesFile .tmp-notes.md -Assets dist/installer/frampp-0.7.0-windows-x64.exe,dist/installer/SHA256SUMS.txt
```

说明：

- 只推 GitHub（`git push`）；`Mirror to Gitee` 工作流会自动把更新推送到 Gitee。
- Gitee 附件单文件上限 **100MB**；Linux `.run` 安装包（超过 100MB）仅在 GitHub 提供。
- 脚本幂等：Release 不存在时创建，附件重复上传不会产生重复文件。

## 0.3.0 Slim Build / 0.3.0 精简构建

FRAMPP 0.3.0 slims the Linux x86_64 package without changing functionality:

- **MariaDB** is now compiled from source (`installer/scripts/linux/build-mariadb.sh`): heavy storage engines and plugins (RocksDB / Mroonga / Connect / Spider / Sphinx / S3 / OQGraph / TokuDB / Archive / Blackhole) are disabled, binaries are stripped, and `mysql-test/ sql-bench/ man/ include/ lib/*.a` are removed. Target size: 30–50 MB, keeping mysqld / mysql / mysqladmin / mysqldump / mysql_install_db.
- **FrankenPHP** is built from source (`installer/scripts/linux/build-frankenphp.sh`): the default PHP extensions drop `intl / soap / gmp / bcmath / exif / imagick`; Caddy modules drop Mercure / Vulcain and add **Souin** (HTTP cache); built with `SPC_LIBC=glibc` (mostly static) and UPX compression (`-w -s` symbols stripped).
- **Python 3.13** is bundled as a slim self-contained runtime (`python-build-standalone` install_only_stripped; `include/ share/`, Tcl/Tk native libs and dev configs are removed, ~30 MB) and added to `PATH` via the `bin/frampp` wrapper.

Build time on CI is expected to grow to roughly 1.5–2 hours per Linux package job.

### glibc baseline / glibc 基线

The Linux x86_64 package is portable across distributions: **FrankenPHP is built as a fully static musl binary** (no glibc dependency, runs on any glibc version and even Alpine), while **MySQL 8.0 uses the official glibc 2.17 generic build** (CentOS 7 baseline), so it runs on CentOS 7 / Ubuntu 20.04+ / Debian 11+ / RHEL 8+ / RHEL 9 (glibc 2.34). MySQL bundles its own OpenSSL / Kerberos / LDAP libraries in `lib/private` and does not depend on systemd; the server only needs `libaio` at runtime.

Linux x86_64 包具备跨发行版可移植性：**FrankenPHP 以 musl 完全静态方式构建**（不依赖 glibc，可运行于任意 glibc 版本甚至 Alpine），**MySQL 8.0 采用官方 glibc 2.17 通用构建**（CentOS 7 基线），因此可在 CentOS 7 / Ubuntu 20.04+ / Debian 11+ / RHEL 8+ / RHEL 9（glibc 2.34）上运行。MySQL 自带 OpenSSL / Kerberos / LDAP 库（`lib/private`），不依赖 systemd；服务端运行时仅需 `libaio`。

The build script `installer/scripts/linux/build-frankenphp-musl.sh` (Alpine, musl static) and the trimmed MySQL module (`installer/scripts/linux/trim-mysql.sh`, official glibc 2.17 minimal tarball) keep the produced binaries on a wide-compatibility baseline; CI asserts `PORTABLE_OK` (FrankenPHP static + MySQL GLIBC ≤ 2.17) during the smoke test.

构建脚本 `installer/scripts/linux/build-frankenphp-musl.sh`（Alpine，musl 静态）与 MySQL 裁剪模块（`installer/scripts/linux/trim-mysql.sh`，官方 glibc 2.17 minimal 包）把产物锁定在广泛兼容的基线上；CI 冒烟测试断言 `PORTABLE_OK`（FrankenPHP 静态 + MySQL GLIBC ≤ 2.17）。

FRAMPP 0.3.0 对 Linux x86_64 安装包做精简，功能保持不变：

- **MariaDB** 改为源码编译（`installer/scripts/linux/build-mariadb.sh`）：禁用 RocksDB / Mroonga / Connect / Spider / Sphinx / S3 / OQGraph / TokuDB / Archive / Blackhole 等重型引擎与插件，二进制 strip，删除 `mysql-test/ sql-bench/ man/ include/ lib/*.a`；目标体积 30~50 MB，保留 mysqld / mysql / mysqladmin / mysqldump / mysql_install_db。
- **FrankenPHP** 改为源码定制构建（`installer/scripts/linux/build-frankenphp.sh`）：PHP 扩展去掉 `intl / soap / gmp / bcmath / exif / imagick`；Caddy 模块去掉 Mercure / Vulcain，加入 **Souin**（HTTP 缓存）；`SPC_LIBC=glibc`（mostly static）+ UPX 压缩（`-w -s` 去符号）。
- **Python 3.13** 内置精简独立运行时（python-build-standalone install_only_stripped；删除 include/share、Tcl/Tk 原生库与开发配置，约 30 MB），`bin/frampp` 包装器自动将其加入 PATH。

CI 构建时间预计增加到每个 Linux 打包作业约 1.5~2 小时。

## 0.4.0 Caddy Access Filter / 0.4.0 集成 Caddy Access Filter

FRAMPP 0.4.0 adds the `caddy-access-filter` Caddy module to the Linux FrankenPHP
custom build:

- Caddy module ID: `http.handlers.access_filter`
- Caddyfile directives: `access` / `filter`
- Pinned module: `github.com/wangbo5825/caddy-access-filter@v1.0.0`
- Default behavior: transparent passthrough unless `access` or `filter` is
  configured with a processor upstream.

FRAMPP 0.4.0 在 Linux FrankenPHP 定制构建中集成 `caddy-access-filter` Caddy
模块：

- Caddy 模块 ID：`http.handlers.access_filter`
- Caddyfile 指令：`access` / `filter`
- 锁定模块：`github.com/wangbo5825/caddy-access-filter@v1.0.0`
- 默认行为：未配置处理器时透明透传。

## 0.6.0 Layout & IP Access Control / 0.6.0 布局与 IP 访问控制

FRAMPP 0.6.0 重构了安装后布局并加入 IP 访问控制：

- 软件模块统一到 `modules/`（frankenphp / mariadb / redis / python / agent /
  control-panel / templates），配置集中到 `etc/`，运行时数据由 `data/` 改为
  `var/`。
- `bin/` 统一命令：`frampp`、`php`、`composer`、`python`、`pip`、`mysql`、
  `redis-cli`、`env`、`uninstall`、`framppd`、`install-systemd`；Linux 用符号
  链接，Windows 用 `.cmd` 包装。
- 安装包不再携带 `install.sh` 与构建脚本；`.run` 解压后调用 `bin/frampp init`。
- Linux systemd 集成：`bin/install-systemd` 安装开机自启服务。
- `caddy-access-filter` 升级到 **v1.2.0**：支持本地 IP / CIDR / `code:XX`
  国家地区码规则与 GeoIP（mmdb / cidr_csv / range_csv）；控制面板
  `http://127.0.0.1:8081/` 新增 IP 访问控制管理，规则写入
  `etc/access-filter.rules` 并通过 Caddy admin API 热重载。

FRAMPP 0.6.0 restructures the installed layout and adds IP access control:

- Components live under `modules/`, configs under `etc/`, and runtime data moved
  from `data/` to `var/`.
- `bin/` provides unified commands (`frampp`, `php`, `composer`, `python`,
  `pip`, `mysql`, `redis-cli`, `env`, `uninstall`, `framppd`,
  `install-systemd`); symlinks on Linux, `.cmd` wrappers on Windows.
- The package no longer ships `install.sh` or build scripts; the `.run` calls
  `bin/frampp init` after extraction.
- Linux systemd integration via `bin/install-systemd`.
- `caddy-access-filter` is upgraded to **v1.2.0** with local IP / CIDR /
  `code:XX` country rules and GeoIP (mmdb / cidr_csv / range_csv); the control
  panel at `http://127.0.0.1:8081/` now manages IP access rules, saved to
  `etc/access-filter.rules`, with hot reload through the Caddy admin API.

产物位于 / Artifacts in `dist/installer/`：

- `frampp-<version>-<env>.exe`（如 `frampp-0.7.0-windows-x64.exe`）：Inno Setup 一键安装包（安装时自动初始化并启动三件套；卸载自动停服清理）/ one-click Windows installer (auto init + start; uninstall stops services and cleans up)
- `frampp-<version>-linux-x86_64.run`（如 `frampp-0.7.0-linux-x86_64.run`）：Linux 自解压单文件安装器（运行后自动校验、解压、初始化并启动；目录可整体移动）/ self-extracting single-file Linux installer (verifies, extracts, initializes and starts; directory relocatable)
- `ghcr.io/wangbo5825/frampp:<version>`：单镜像 all-in-one Docker 镜像（首启动初始化，`docker run` / Compose 一键启动）/ single all-in-one Docker image (initializes on first start; one-click via `docker run` / Compose)
- `SHA256SUMS.txt`：全部安装包哈希，供用户核对 / hashes of all installers for verification

## 0.7.0 MySQL 8.0 / 0.7.0 切换 MySQL 8.0

FRAMPP 0.7.0 switches the Linux database component from a source-built
MariaDB to the official **MySQL 8.0.46 Community** generic binary
(`linux-glibc2.17-x86_64-minimal.tar.xz`), trimmed by
`installer/scripts/linux/trim-mysql.sh`:

- The official glibc 2.17 build targets CentOS 7 and is backward-compatible
  with newer distributions; OpenSSL / Kerberos / LDAP / SASL are bundled in
  `lib/private`, so there is no system OpenSSL dependency and no systemd
  requirement. Only `libaio` is needed at runtime.
- Removed during trimming: `lib/mecab` dictionaries (~129 MB), Kerberos /
  LDAP-SASL / OCI / FIDO authentication plugins, group replication,
  sample/test plugins, non-core CLI tools, headers, docs, man pages and
  localized error messages except English. The module targets ~30–45 MB
  compressed.
- Database init uses `mysqld --initialize-insecure` + PHP PDO (mysqlnd) over
  a unix socket, so the `mysql` CLI's `libtinfo.so.5` dependency is not
  required at install time.
- Notes: MySQL 8.0 reached EOL on 2026-04-30 (8.0.46 is the final release)
  and is adopted as the CentOS 7-compatible baseline; a dual-variant switch
  to MySQL 8.4 LTS / MariaDB 11.4 for modern distributions is planned next.
  MariaDB data directories are **not** compatible with MySQL 8.0 — upgrading
  from 0.6.0 requires rebuilding the database (see
  [docs/user/upgrade.md](user/upgrade.md)).

FRAMPP 0.7.0 将 Linux 数据库组件由源码编译 MariaDB 切换为官方
**MySQL 8.0.46 Community** 通用二进制（`linux-glibc2.17-x86_64-minimal`），
由 `installer/scripts/linux/trim-mysql.sh` 裁剪：

- 官方 glibc 2.17 构建以 CentOS 7 为目标，且对更新发行版向后兼容；
  OpenSSL / Kerberos / LDAP / SASL 打包在 `lib/private`，无系统 OpenSSL
  依赖、无 systemd 依赖，服务端运行时仅需 `libaio`。
- 裁剪删除：`lib/mecab` 词典（约 129MB）、Kerberos / LDAP-SASL / OCI /
  FIDO 认证插件、组复制、示例/测试插件、非核心 CLI 工具、头文件、文档、
  man 页与除英文外的本地化错误消息；模块目标压缩体积约 30~45MB。
- 初始化使用 `mysqld --initialize-insecure` + PHP PDO（mysqlnd，走 unix
  socket），安装期不依赖 `mysql` CLI 的 `libtinfo.so.5`。
- 说明：MySQL 8.0 已于 2026-04-30 EOL（8.0.46 为最终版），作为 CentOS 7
  兼容基线采用；面向现代发行版的 MySQL 8.4 LTS / MariaDB 11.4 双变体切换
  已列入后续计划。MariaDB 数据目录与 MySQL 8.0 **不兼容**——从 0.6.0 升级
  需重建数据库（见 [docs/user/upgrade.md](user/upgrade.md)）。

## 0.7.2 caddy-access-filter 1.2.1 / 0.7.2 升级 caddy-access-filter 1.2.1

FRAMPP 0.7.2 upgrades the `caddy-access-filter` module pinned in the Linux
FrankenPHP custom build to **v1.2.1** (bug-fix release of the IP access
filter). Stale v1.2.0 references in the build cache marker and script comments
were fixed at the same time.

FRAMPP 0.7.2 将 Linux FrankenPHP 定制构建中锁定的 `caddy-access-filter`
模块升级到 **v1.2.1**（IP 访问过滤模块的错误修正版本），并同步修正构建缓存
标记与脚本注释中残留的 v1.2.0 引用。

## Linux 一键安装（用户侧）/ Linux One-Click Install (user side)

```bash
chmod +x frampp-0.7.0-linux-x86_64.run
./frampp-0.7.0-linux-x86_64.run                 # 默认安装到 ~/frampp / installs to ~/frampp
./frampp-0.7.0-linux-x86_64.run --prefix /opt/frampp   # 自定义目录 / custom directory
./frampp-0.7.0-linux-x86_64.run --help           # 帮助 / help

~/frampp/bin/frampp status        # 查看服务状态 / check status
~/frampp/bin/uninstall            # 停止服务并可选清理数据 / stop services, optionally clean data
```

Linux 包自包含三件套二进制（FrankenPHP 静态构建、MySQL 8.0 glibc 2.17 裁剪版、Redis 官方源码静态编译），不依赖系统包管理器；运行时仅需常见工具（sh / tar / openssl 或 /dev/urandom）与 libaio（Debian/Ubuntu 需安装 libaio1）。
The Linux package bundles all three binaries (static FrankenPHP, a trimmed MySQL 8.0 glibc 2.17 build, statically compiled Redis) with no system package dependencies; only common tools are needed at runtime (sh / tar / openssl or /dev/urandom) plus libaio (libaio1 on Debian/Ubuntu).

## 新增通道 / Adding a Channel

1. 确认目标组件矩阵 / Confirm the component matrix (e.g. FrankenPHP provides a PHP 8.4 Windows build)
2. 按环境新增版本清单 / Add a version manifest per environment（Windows：`installer/config/versions.json`；Linux：`installer/config/versions-linux-x86_64.json`）
3. 在 `installer/config/channels.json` 注册通道 / Register the channel（`id`、`label`、`default`、`envs`）
4. 跑 / Run `release.ps1 -Channel <新通道/new channel>` 验证构建与测试 / to verify build & tests

## 校验 / Verification

```powershell
Get-FileHash frampp-0.7.0-windows-x64.exe -Algorithm SHA256
sha256sum frampp-0.7.0-linux-x86_64.run
# 与 / compare with SHA256SUMS.txt 中对应行 / the matching line
```
