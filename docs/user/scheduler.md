# FRAMPP 定时任务 / Scheduler

> 适用版本：v0.8.2 Linux 定制构建（x86_64 / aarch64）。Windows 官方
> FrankenPHP 构建不含该模块。

FRAMPP 集成 [pogo_scheduler v0.1.0](https://github.com/wangbo5825/scheduler)
（`pogo_scheduler`，Caddy / FrankenPHP 内嵌调度器）。配置文件为
`etc/scheduler.caddy`，由 `etc/Caddyfile` 的全局配置块导入；默认内容只有注释，
即**默认不启用**。

修改 `etc/scheduler.caddy` 后执行：

```bash
bin/frampp restart frankenphp
```

调度事件写入 FrankenPHP 日志（`logs/frankenphp.log` / `logs/frankenphp.err.log`）。
也可以在 caddy-panel（`http://127.0.0.1:8081/panel`）的日志页查看。

## 模式 1：HTTP 任务（推荐）

不启动外部进程，由 Caddy 向自身（或其它 HTTP 服务）发起请求，交给常驻 PHP
worker 处理，安全面和开销都更小：

```caddy
pogo_scheduler {
    mode     http
    url      http://127.0.0.1:8080/scheduler/run
    method   POST
    header   Content-Type application/json
    body     "{\"source\":\"frampp\"}"
    expect_status 200
    interval 1m
    timeout  30s
    overlap  skip
}
```

`interval` 支持 `30s` / `1m` / `5m` 等；也可用 `schedule` 指定 cron 表达式
（标准 5 段、`@every 5m`、可选 `CRON_TZ=Zone` 前缀）。`overlap` 取 `skip`
（上次未结束则跳过）或 `allow`。

## 模式 2：外部命令

与上游兼容，调度器会启动外部进程；请只配置可信命令：

```caddy
pogo_scheduler {
    mode     command
    command  /opt/frampp/modules/frankenphp/frankenphp php-cli /opt/frampp/apps/default/bin/console schedule:run
    dir      /opt/frampp
    interval 1m
    timeout  5m
    overlap  skip
}
```

## 命名参数速查

| 参数 | 说明 |
| --- | --- |
| `mode` | `http` 或 `command`（省略时按 `url` / `command` 推断） |
| `url` / `method` / `header` / `body` / `expect_status` | HTTP 任务参数 |
| `command` / `dir` | 命令任务与工作目录 |
| `interval` / `schedule` | 间隔或 cron 表达式（`schedule` 优先） |
| `timeout` / `overlap` / `shutdown_grace` | 执行超时、重叠策略、停机等待 |

## 安全建议

- 优先使用 HTTP 模式：调度器不获得执行任意 shell 命令的能力。
- 任务端点应校验来源/令牌（例如固定 `Authorization` 头），只监听本机。
- 命令模式只在必要时使用，命令与参数必须固定、可信，避免拼接用户输入。
- 调度器只负责“何时触发”；任务幂等、重试与并发控制仍由应用实现。

## 兼容性

- **Linux x86_64 / aarch64**：0.8.2 定制构建内置 `pogo_scheduler`。
- **Windows**：官方预编译 FrankenPHP 不含该模块，`etc/scheduler.caddy` 不会被导入；
  可使用 Windows 任务计划程序调用应用 CLI 作为等价方案。
- 检查模块是否存在：`modules/frankenphp/frankenphp list-modules | grep pogo_scheduler`。
