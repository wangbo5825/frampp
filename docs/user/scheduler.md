# FRAMPP 定时任务 / Scheduler

> 适用版本：v0.8.4+ Linux 定制构建（x86_64 / aarch64）。Windows 官方
> FrankenPHP 构建不含该模块。

FRAMPP 集成 [pogo_scheduler v0.2.0](https://github.com/wangbo5825/scheduler)
（`pogo_scheduler`，Caddy / FrankenPHP 内嵌调度器）。配置文件为
`etc/scheduler.caddy`，由 `etc/Caddyfile` 的全局配置块导入；默认内容只有注释，
即**默认不启用**。

修改 `etc/scheduler.caddy` 后执行：

```bash
bin/frampp restart frankenphp
```

调度事件写入 FrankenPHP 日志（`logs/frankenphp.log` / `logs/frankenphp.err.log`）。
也可以在 caddy-panel（`http://127.0.0.1:8081/panel`）的日志页查看。

## 多个任务（v0.2.0）

不启动外部进程，由 Caddy 向自身（或其它 HTTP 服务）发起请求，交给常驻 PHP
worker 处理，安全面和开销都更小。每个 `job` 拥有独立的时间表、超时与重叠策略：

```caddy
pogo_scheduler {
    shutdown_grace 30s

    job heartbeat {
        mode     http
        url      http://127.0.0.1:8080/scheduler/heartbeat
        interval 1m
        timeout  30s
        overlap  skip
    }

    job nightly {
        mode     http
        url      http://127.0.0.1:8080/scheduler/nightly
        method   POST
        header   Content-Type application/json
        body     "{\"source\":\"frampp\"}"
        schedule "0 3 * * *"
        timeout  10m
        overlap  skip
    }
}
```

`job <name>` 名称必须唯一。顶层参数不能与 `job` 块混用；`shutdown_grace`
是全局参数，始终放在各个 `job` 之外。

`interval` 支持 `30s` / `1m` / `5m` 等；也可用 `schedule` 指定 cron 表达式
（标准 5 段、`@every 5m`、可选 `CRON_TZ=Zone` 前缀）。`overlap` 取 `skip`
（上次未结束则跳过）或 `allow`。

## 外部命令任务

与上游兼容，调度器会启动外部进程；请只配置可信命令：

```caddy
pogo_scheduler {
    job cleanup {
        mode     command
        command  /opt/frampp/modules/frankenphp/php /opt/frampp/apps/default/bin/console cleanup
        dir      /opt/frampp
        interval 5m
        timeout  2m
        overlap  skip
    }
}
```

## v0.1.0 配置兼容

v0.1.0 的顶层单任务语法仍可使用，无需改写；但不要在同一
`pogo_scheduler` 块中混用顶层任务参数和 `job` 块。

```caddy
pogo_scheduler {
    mode     http
    url      http://127.0.0.1:8080/scheduler/run
    interval 1m
    timeout  30s
    overlap  skip
}
```

## 任务参数速查

| 参数 | 说明 |
| --- | --- |
| `mode` | `http` 或 `command`（省略时按 `url` / `command` 推断） |
| `job <name>` | v0.2.0 命名任务；每个任务独立调度 |
| `url` / `method` / `header` / `body` / `expect_status` | HTTP 任务参数 |
| `command` / `dir` | 命令任务与工作目录 |
| `interval` / `schedule` | 间隔或 cron 表达式（`schedule` 优先） |
| `timeout` / `overlap` | 任务级执行超时与重叠策略 |
| `shutdown_grace` | 全局停机等待，放在 `pogo_scheduler` 顶层 |

## 安全建议

- 优先使用 HTTP 模式：调度器不获得执行任意 shell 命令的能力。
- 任务端点应校验来源/令牌（例如固定 `Authorization` 头），只监听本机。
- 命令模式只在必要时使用，命令与参数必须固定、可信，避免拼接用户输入。
- 调度器只负责“何时触发”；任务幂等、重试与并发控制仍由应用实现。

## 兼容性

- **Linux x86_64 / aarch64**：0.8.2+ 定制构建；0.8.4 起内置
  `pogo_scheduler` v0.2.0 多任务能力。
- **Windows**：官方预编译 FrankenPHP 不含该模块，`etc/scheduler.caddy` 不会被导入；
  可使用 Windows 任务计划程序调用应用 CLI 作为等价方案。
- 检查模块是否存在：`modules/frankenphp/frankenphp list-modules | grep pogo_scheduler`。
