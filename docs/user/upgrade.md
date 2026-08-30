# FRAMPP 安装、升级与卸载 / Install, Upgrade & Uninstall

## 安装 / Install

运行 / Run `frampp-setup-<version>-windows-x64.exe`（安装器由 / installer built by `installer/scripts/build-installer.ps1`，产物在 / artifacts in `dist/installer/`）。

安装过程自动完成 / The installer automatically:

1. 解压 FrankenPHP / MariaDB / Redis / Composer / APCu / Adminer 到安装目录（默认 / default `C:\Program Files\FRAMPP`）/ extracts components into the install directory
2. 运行 / Runs `installer/scripts/init.ps1`：生成配置（etc/php.ini / etc/redis.conf / etc/Caddyfile）、随机密钥（`var/secrets.json`）、初始化 MariaDB 数据目录与只读账号 / generates configs, random secrets, initializes the MariaDB datadir & read-only account
3. 启动三件套并打开控制面板（`http://127.0.0.1:8081/`）/ starts the stack and opens the control panel

### Linux（x86_64）

```bash
chmod +x frampp-setup-8.5-0.6.0-linux-x86_64.run
./frampp-setup-8.5-0.6.0-linux-x86_64.run                 # 默认安装到 ~/frampp / installs to ~/frampp
./frampp-setup-8.5-0.6.0-linux-x86_64.run --prefix /opt/frampp   # 自定义目录 / custom directory
```

单文件安装器会自动校验完整性、解压并执行 `bin/frampp init`
（生成配置、随机密钥、初始化 MariaDB 数据目录与只读账号）并启动三件套；安装目录可整体移动。
The single-file installer verifies integrity, extracts, runs `init.sh` (configs, secrets, MariaDB datadir & read-only account) and starts the stack; the install directory is relocatable.

> 系统要求：Linux x86_64 需 glibc ≥ 2.31（Ubuntu 20.04+ / Debian 11+ / RHEL 9+）；FrankenPHP 与 Redis 为 musl 静态，MariaDB 以 glibc 2.31 为基线且不依赖 libaio。完整系统要求与安装包校验见 `docs/README.md`。
> Requirement: Linux x86_64 needs glibc ≥ 2.31 (Ubuntu 20.04+ / Debian 11+ / RHEL 9+); FrankenPHP and Redis are musl-static and MariaDB targets a glibc 2.31 baseline without libaio. See `docs/README.md` for full requirements and installer verification.

## 升级 / Upgrade

组件版本锁定在 / Component versions are pinned in `installer/config/versions.json`，FRAMPP 版本号随 Release 递增 / FRAMPP version bumps per release。

升级步骤 / Steps:

1. **备份数据（重要）/ Back up data (important)**：复制安装目录下的 `var/`（MariaDB 数据、密钥）与 `htdocs/` 中的项目 / copy `var/` and your projects in `htdocs/`
2. 停止服务 / Stop services：`bin/frampp stop all`
3. 运行新版本安装器，覆盖安装到同一目录 / Run the new installer over the same directory（Inno Setup 会保留 / keeps `var/` 与 / and `logs/`）
4. 安装完成后 `init.ps1` 会复用已有密钥与数据目录（幂等），无需重新初始化 / init is idempotent and reuses existing secrets & datadir
5. 用 / Verify with `bin/frampp status` 与 / and `logs`

> 版本间数据库结构变化（如 MariaDB 大版本升级）时，建议先在备份上演练；必要时用 `mariadb-upgrade`。
> If the database schema changes between versions (e.g. a MariaDB major upgrade), rehearse on a backup first; use `mariadb-upgrade` if needed.

## 卸载 / Uninstall

Windows：使用开始菜单的“卸载 FRAMPP”或运行 / use "Uninstall FRAMPP" in the Start menu or run `unins000.exe`。卸载器会 / The uninstaller:

1. 先停止三件套服务 / Stops all services（`frampp stop all` + taskkill fallback）
2. 删除安装目录、`var/`、`logs/` 及 init 生成的 Caddyfile / php.ini / redis.conf / Removes the install dir, `var/`, `logs/` and generated configs

> 卸载会**删除 MariaDB 数据**，卸载前请确认已备份需要保留的项目与数据。
> Uninstall **deletes MariaDB data**; make sure to back up projects & data first.

Linux：运行 / Run `./bin/uninstall`，先停止服务，再选择是否删除 / it stops services, then asks whether to delete `var/` 与 / and `logs/`；完全移除时删除整个目录 / delete the whole directory to fully remove。

## 版本查看 / Check Version

```powershell
bin/frampp version
```

Linux 下使用 / On Linux use `./bin/frampp version`。
