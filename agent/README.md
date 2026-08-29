# Agent（MCP 服务器）

FRAMPP 的 AI 接入层：把本地环境能力封装为 MCP 工具，供 Claude Code、Cursor、Codex 等 AI 编码工具调用。

- 设计：`docs/blueprint.md` §5
- 协议：MCP（Model Context Protocol），v0.1 提供 **stdio** 传输（JSON-RPC 2.0，新行分隔）
- 实现：**零外部依赖**的 PHP 实现（自研轻量传输层；工具用 `#[AsTool]` 注解声明，与 php-mcp 风格一致，便于未来迁移官方 SDK）
- 安全基线：默认仅绑定 127.0.0.1；MariaDB 独立只读账号 + 强制 LIMIT；Redis 只读命令白名单；命令固定模板白名单；全部工具调用写审计日志（`logs/agent-audit.log`）

## 工具清单（v0.1）

| 工具 | 说明 |
| --- | --- |
| `mysql.list_tables` / `mysql.describe` / `mysql.query` | 只读；自动加 LIMIT |
| `redis.keys` / `redis.get` / `redis.ttl` / `redis.info` | SCAN / GET / TTL / INFO，只读白名单 |
| `logs.tail` / `logs.search` | 日志查看，路径白名单（仅 `logs/`） |
| `env.php_version` / `env.composer_show` / `env.services_status` / `env.project_info` | 固定命令模板，不接受任意命令 |

## 运行

```powershell
# 直接运行（自动发现 FRAMPP 运行时；也可 --home 指定）
bin/frampp-mcp

# 客户端接入示例（Claude Code / Cursor / Codex 的 mcpServers 配置）
# {
#   "mcpServers": {
#     "frampp": {
#       "command": "bin/frampp-mcp",
#       "args": ["--home", "C:/path/to/runtime"]
#     }
#   }
# }
```

配置：复制 `config/frampp-mcp.json.example` 为 `config/frampp-mcp.json`（`project` 指向要开放给 Agent 的项目目录）。

## 安全边界

- 数据库使用 `frampp_ro` 只读账号（`init.ps1` 创建，仅 SELECT / SHOW VIEW）
- 查询强制：仅 `SELECT / SHOW / DESCRIBE / EXPLAIN`，自动附加 `LIMIT`（上限 1000 行）
- Redis 只实现只读命令子集的 RESP 客户端，其余命令在协议层直接拒绝
- 日志工具仅允许 `logs/` 目录内文件（realpath 校验）
- 审计：每个工具调用的时间、参数与结果大小写入 `logs/agent-audit.log`
