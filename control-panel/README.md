# 控制面板

仿 XAMPP 的图形 / 命令行控制台：服务启停、状态查看、端口冲突检测、日志查看、密码管理。

- M1 交付：MVP（启停 / 状态 / 端口 / 日志）

## 组成

- `bin/frampp`：PHP CLI 入口（`status` / `start` / `stop` / `logs` / `ports`）
- `src/Config.php`：运行时定位（`FRAMPP_HOME` → 安装布局 → `dist/runtime`）
- `src/ServiceManager.php`：服务启停 / 状态 / 端口 / 日志核心
- `src/AccessManager.php`：IP 访问控制（规则文件、GeoIP、Caddy 热重载）
- `web/`：浏览器 UI，由 FrankenPHP 在 `127.0.0.1:8081` 提供服务

## CLI 用法

```powershell
php control-panel/bin/frampp status          # 三件套状态
php control-panel/bin/frampp start all       # 启动全部
php control-panel/bin/frampp stop mariadb    # 停止单个服务
php control-panel/bin/frampp logs redis 100  # 最近 100 行日志
php control-panel/bin/frampp ports --json
php control-panel/bin/frampp version        # 版本与组件版本
php control-panel/bin/frampp new-project my-app minimal   # 一键创建项目
php control-panel/bin/frampp new-project api minimal      # 别名：minimal 离线模板
php control-panel/bin/frampp new-project app symfony      # composer create-project symfony/skeleton
php control-panel/bin/frampp new-project app api-platform # symfony/skeleton + composer require api-platform/core
php control-panel/bin/frampp ip-access status             # IP 访问控制状态与规则
php control-panel/bin/frampp ip-access add 203.0.113.10 block
php control-panel/bin/frampp ip-access default block
php control-panel/bin/frampp ip-access reload
```

项目创建到 `htdocs/<name>`；`minimal` 为离线模板（无需网络），`symfony` / `api-platform` 依赖网络与内置 Composer。
数据库管理：`http://127.0.0.1:8080/adminer.php`（Adminer，由 `init.ps1` 随包安装）。

## 安全

- Web 端仅绑定 `127.0.0.1`；启停操作需 `var/secrets.json` 中的 `panel_token`
- 服务 PID 由控制面板统一管理（`var/*.pid`），不注册系统服务
- IP 访问控制仅 Linux 定制构建可用（Windows 官方构建未内置 `caddy-access-filter`）
