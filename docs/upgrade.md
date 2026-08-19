# FRAMPP 安装、升级与卸载

## 安装

运行 `frampp-setup-<version>.exe`（安装器由 `installer/scripts/build-installer.ps1` 构建，产物在 `dist/installer/`）。

安装过程自动完成：

1. 解压 FrankenPHP / MariaDB / Redis / Composer / APCu / Adminer 到安装目录（默认 `C:\Program Files\FRAMPP`）
2. 运行 `installer/scripts/init.ps1`：生成配置（php.ini / redis.conf / Caddyfile）、随机密钥（`data/secrets.json`）、初始化 MariaDB 数据目录与只读账号
3. 启动三件套并打开控制面板（`http://127.0.0.1:8081/`）

## 升级

组件版本锁定在 `installer/config/versions.json`，FRAMPP 版本号随 Release 递增。

升级步骤：

1. **备份数据**（重要）：复制安装目录下的 `data/`（MariaDB 数据、密钥）与 `htdocs/` 中的项目
2. 停止服务：`php control-panel/bin/frampp stop all`
3. 运行新版本安装器，覆盖安装到同一目录（Inno Setup 会保留 `data/` 与 `logs/`，见 `[UninstallDelete]` 仅卸载时生效）
4. 安装完成后 `init.ps1` 会复用已有密钥与数据目录（幂等），无需重新初始化
5. 用 `php control-panel/bin/frampp status` 与 `logs` 验证

> 版本间数据库结构变化（如 MariaDB 大版本升级）时，建议先在备份上演练；必要时用 `mariadb-upgrade`。

## 卸载

使用开始菜单的“卸载 FRAMPP”或运行 `unins000.exe`。卸载器会：

1. 先停止三件套服务（`frampp stop all` + 兜底 taskkill）
2. 删除安装目录、`data/`、`logs/` 及 init 生成的 Caddyfile / php.ini / redis.conf

> 卸载会**删除 MariaDB 数据**，卸载前请确认已备份需要保留的项目与数据。

## 版本查看

```powershell
php control-panel/bin/frampp version
```
