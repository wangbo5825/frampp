# 控制面板

仿 XAMPP 的图形 / 命令行控制台：服务启停、状态查看、端口冲突检测、日志查看、密码管理。

- M1 交付：MVP（启停 / 状态 / 端口 / 日志）

## 组成

- `bin/frampp`：PHP CLI 入口（`status` / `start` / `stop` / `logs` / `ports`）
- `bin/start-service.ps1`：Windows 进程拉起适配层（隐藏窗口 + PID 落盘）
- `src/Config.php`：运行时定位（`FRAMPP_HOME` → 安装布局 → `dist/runtime`）
- `src/ServiceManager.php`：服务启停 / 状态 / 端口 / 日志核心
- `web/`：浏览器 UI，由 FrankenPHP 在 `127.0.0.1:8081` 提供服务

## CLI 用法

```powershell
php control-panel/bin/frampp status          # 三件套状态
php control-panel/bin/frampp start all       # 启动全部
php control-panel/bin/frampp stop mariadb    # 停止单个服务
php control-panel/bin/frampp logs redis 100  # 最近 100 行日志
php control-panel/bin/frampp ports --json
```

## 安全

- Web 端仅绑定 `127.0.0.1`；启停操作需 `data/secrets.json` 中的 `panel_token`
- 服务 PID 由控制面板统一管理（`data/*.pid`），不注册系统服务
