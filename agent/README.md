# Agent（MCP 服务器）

FRAMPP 的 AI 接入层：把本地环境能力封装为 MCP 工具，供 Claude Code、Cursor、Codex 等 AI 编码工具调用。

- 设计：`docs/blueprint.md` §5
- 实现选型：PHP 优先（`php-mcp`，PHP 基金会合作维护）
- 安全基线：默认仅绑定 127.0.0.1；只读数据库账号；命令白名单；审计日志
