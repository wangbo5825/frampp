# FRAMPP 版本发布 / FRAMPP Releases

## 发布模型 / Release Model

产品定位：**面向普通用户的一键安装**（类似 XAMPP），按 **FRAMPP 版本 × 组件通道 × 环境** 发布不同的一键安装包；**不提供**高级用户的多 PHP 版本并存（Laragon / Herd 式）。

Positioning: **one-click installers for everyday users** (XAMPP-style), published per **FRAMPP version × component channel × environment**; we do **not** provide multi-PHP coexistence for power users (Laragon / Herd style).

命名规则 / Naming:

```text
frampp-setup-<channel>-<version>-<env>.<ext>
示例 / e.g. frampp-setup-8.5-0.3.0-windows-x64.exe
示例 / e.g. frampp-setup-8.5-0.3.0-linux-x86_64.run
```

- `<channel>`：组件通道 / component channel（当前 / current `8.5` = FrankenPHP 1.12.7 / PHP 8.5.9 / MariaDB 12.3.2 / Redis 8.10.1）
- `<version>`：FRAMPP 版本号（语义化，随 Release 递增，来源：仓库 `VERSION` 文件）/ semantic version, bumped per release (from repo `VERSION`)
- `<env>`：目标环境 / target environment（`windows-x64` / `linux-x86_64`；macOS / Docker 属 M5）
- `<ext>`：`.exe`（Windows，Inno Setup）或 `.run`（Linux，自解压单文件安装器 / self-extracting single-file installer）

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

CI 替代方案：Linux 包由 GitHub Actions 构建后，可在 workflow_dispatch 时传入 `release_tag` 自动上传到 Release（`gh workflow run ci.yml -f release_tag=v0.3.0`）。
CI alternative: after the Linux package is built by GitHub Actions, pass `release_tag` on workflow_dispatch to auto-upload to a release (`gh workflow run ci.yml -f release_tag=v0.3.0`).

## Publish to Gitee / 发布到 Gitee

GitHub is the single source of truth. The repository is mirrored to Gitee automatically by the **GitHub Actions workflow** `.github/workflows/mirror-gitee.yml` (on every push to `main`, branches and tags are pushed to Gitee), so **do not push to Gitee manually**. The workflow requires the repository secret `GITEE_TOKEN` (Gitee personal access token, scope: `projects`).

> Note: if you previously enabled Gitee's built-in GitHub mirror sync (管理 → 仓库设置 → 镜像仓库管理), disable it to avoid two-way sync conflicts — the GitHub workflow is now the single sync path.

Gitee mirror sync does **not** copy GitHub Releases, so a Gitee 发行版 (with installer attachments) is optional. If you also publish Gitee releases, use the publish script (requires pwsh 7 and a Gitee token with `projects` scope):

```powershell
pwsh -File installer/scripts/publish-gitee.ps1 -Token $env:GITEE_TOKEN -Tag v0.3.0 `
  -NotesFile .tmp-notes.md -Assets dist/installer/frampp-setup-8.5-0.3.0-windows-x64.exe,dist/installer/SHA256SUMS.txt
```

Notes:

- Push only to GitHub (`git push`); the `Mirror to Gitee` workflow pushes the update to Gitee automatically.
- Gitee attachment limit is **100 MB per file**; the Linux `.run` installer (over 100 MB) stays GitHub-only.
- The script is idempotent: it creates the release when missing and uploads assets without duplicating them.

GitHub 是唯一推送源。仓库由 **GitHub Actions 工作流** `.github/workflows/mirror-gitee.yml` 自动镜像到 Gitee（每次 push 到 `main` 时，分支与标签自动推送到 Gitee），**无需再手动推送到 Gitee**。工作流需要仓库级 secret `GITEE_TOKEN`（Gitee 私人令牌，权限含 `projects`）。

> 注意：如之前在 Gitee 侧开启了内置 GitHub 镜像同步（管理 → 仓库设置 → 镜像仓库管理），请停用以避免双向同步冲突——现在由 GitHub 工作流作为唯一同步通道。

镜像同步**不会**复制 GitHub Releases，因此 Gitee 发行版（含安装包附件）为可选项。如仍需发布 Gitee 发行版，运行发布脚本（需要 pwsh 7 与 Gitee 私人令牌，权限含 `projects`）：

```powershell
pwsh -File installer/scripts/publish-gitee.ps1 -Token $env:GITEE_TOKEN -Tag v0.3.0 `
  -NotesFile .tmp-notes.md -Assets dist/installer/frampp-setup-8.5-0.3.0-windows-x64.exe,dist/installer/SHA256SUMS.txt
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

FRAMPP 0.3.0 对 Linux x86_64 安装包做精简，功能保持不变：

- **MariaDB** 改为源码编译（`installer/scripts/linux/build-mariadb.sh`）：禁用 RocksDB / Mroonga / Connect / Spider / Sphinx / S3 / OQGraph / TokuDB / Archive / Blackhole 等重型引擎与插件，二进制 strip，删除 `mysql-test/ sql-bench/ man/ include/ lib/*.a`；目标体积 30~50 MB，保留 mysqld / mysql / mysqladmin / mysqldump / mysql_install_db。
- **FrankenPHP** 改为源码定制构建（`installer/scripts/linux/build-frankenphp.sh`）：PHP 扩展去掉 `intl / soap / gmp / bcmath / exif / imagick`；Caddy 模块去掉 Mercure / Vulcain，加入 **Souin**（HTTP 缓存）；`SPC_LIBC=glibc`（mostly static）+ UPX 压缩（`-w -s` 去符号）。
- **Python 3.13** 内置精简独立运行时（python-build-standalone install_only_stripped；删除 include/share、Tcl/Tk 原生库与开发配置，约 30 MB），`bin/frampp` 包装器自动将其加入 PATH。

CI 构建时间预计增加到每个 Linux 打包作业约 1.5~2 小时。

产物位于 / Artifacts in `dist/installer/`：

- `frampp-setup-<channel>-<version>-<env>.exe`：Inno Setup 一键安装包（安装时自动初始化并启动三件套；卸载自动停服清理）/ one-click Windows installer (auto init + start; uninstall stops services and cleans up)
- `frampp-setup-<channel>-<version>-linux-x86_64.run`：Linux 自解压单文件安装器（运行后自动校验、解压、初始化并启动；目录可整体移动）/ self-extracting single-file Linux installer (verifies, extracts, initializes and starts; directory relocatable)
- `SHA256SUMS.txt`：全部安装包哈希，供用户核对 / hashes of all installers for verification

## Linux 一键安装（用户侧）/ Linux One-Click Install (user side)

```bash
chmod +x frampp-setup-8.5-0.3.0-linux-x86_64.run
./frampp-setup-8.5-0.3.0-linux-x86_64.run                 # 默认安装到 ~/frampp / installs to ~/frampp
./frampp-setup-8.5-0.3.0-linux-x86_64.run --prefix /opt/frampp   # 自定义目录 / custom directory
./frampp-setup-8.5-0.3.0-linux-x86_64.run --help           # 帮助 / help

~/frampp/bin/frampp status        # 查看服务状态 / check status
~/frampp/uninstall.sh             # 停止服务并可选清理数据 / stop services, optionally clean data
```

Linux 包自包含三件套二进制（FrankenPHP 静态构建、MariaDB bintar、Redis 官方源码静态编译），不依赖系统包管理器；运行时仅需常见工具（sh / tar / openssl 或 /dev/urandom）。
The Linux package bundles all three binaries (static FrankenPHP, MariaDB bintar, statically compiled Redis) with no system package dependencies; only common tools are needed at runtime (sh / tar / openssl or /dev/urandom).

## 新增通道 / Adding a Channel

1. 确认目标组件矩阵 / Confirm the component matrix (e.g. FrankenPHP provides a PHP 8.4 Windows build)
2. 按环境新增版本清单 / Add a version manifest per environment（Windows：`installer/config/versions.json`；Linux：`installer/config/versions-linux-x86_64.json`）
3. 在 `installer/config/channels.json` 注册通道 / Register the channel（`id`、`label`、`default`、`envs`）
4. 跑 / Run `release.ps1 -Channel <新通道/new channel>` 验证构建与测试 / to verify build & tests

## 校验 / Verification

```powershell
Get-FileHash frampp-setup-8.5-0.1.0-windows-x64.exe -Algorithm SHA256
sha256sum frampp-setup-8.5-0.3.0-linux-x86_64.run
# 与 / compare with SHA256SUMS.txt 中对应行 / the matching line
```
