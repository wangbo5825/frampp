# 安全与指纹 / Security & Fingerprints

## 默认策略 / Default policy

FRAMPP 0.8.5 默认减少无需暴露给远程扫描器的技术信息：

- `expose_php=Off`：移除 `X-Powered-By`。
- `display_errors=Off`、`display_startup_errors=Off`、`html_errors=Off`：
  异常和启动错误不返回浏览器，详细诊断写入日志。
- `zend.exception_ignore_args=On`：异常回溯不包含调用参数。
- `user_agent`：PHP stream wrapper 使用
  `Mozilla/5.0 (compatible; Application)`，不包含 PHP/FRAMPP 版本。
- 托管站点及错误响应删除 `Server`、`X-Powered-By`、`X-Powered-By-PHP`、
  `Via`。
- Caddy 错误页只返回 `Not Found` / `Internal Server Error` 等通用文本。

The defaults are designed to reduce scan fingerprints, not to make the service
anonymous. Application behavior, routes and response content can still identify
the application.

## 自定义站点 / Custom sites

内置 Caddyfile 定义了可复用片段：

```caddy
(frampp_fingerprint_privacy) {
    # defined in etc/global.caddy
}
```

默认站点、控制台和由 FRAMPP 站点管理器新生成的站点会自动导入该片段。
手工维护的 `etc/caddy.d/*.caddy` 站点应添加：

```caddy
example.test {
    import frampp_fingerprint_privacy
    # site routes...
}
```

## 反向代理 / Reverse proxy

客户端 User-Agent 默认原样转发，应用不会看到伪造的浏览器 UA。若某个内部任务
需要统一 UA，应显式配置：

```caddy
reverse_proxy 127.0.0.1:9000 {
    header_up User-Agent "Mozilla/5.0 (compatible; Application)"
}
```

scheduler HTTP 任务的示例同样通过 `header User-Agent ...` 设置通用 UA。

## 本地调试 / Local debugging

需要临时查看 PHP 错误时，只应修改本机 `etc/php.ini`：

```ini
display_errors = On
display_startup_errors = On
```

调试后恢复 `Off` 并执行 `frampp restart frankenphp`。不要把详细错误重新暴露到
可从不受信任网络访问的站点。

## 局限 / Limitations

- 隐藏 PHP 版本不能替代及时升级；0.8.5 已升级到 PHP 8.5.13 /
  FrankenPHP 1.13.6。
- 响应头和错误页不会隐藏应用自身的框架、路由、Cookie 或业务错误。
- 服务器内部日志仍可能记录 PHP/FrankenPHP 版本，应通过文件权限和控制面板访问
  控制保护。
