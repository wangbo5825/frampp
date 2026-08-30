# FRAMPP 用户文档 / User Documentation

随发布包附带的用户文档。安装后在 `docs/` 目录下可找到（Windows 安装器与
Linux 安装包均包含本目录内容）。

User documentation shipped with the installers (Windows `.exe` and Linux `.run`
include this directory under `docs/`).

## 文档 / Documents

- [安装、升级与卸载 / Install, Upgrade & Uninstall](upgrade.md)
- [Docker 镜像使用 / Docker Image Usage](docker.md)
- 快速开始 / Quick Start：安装目录下的 `README.md`（项目概览 / project overview）

## 系统要求 / System Requirements

- **Windows** — x64，Windows 10 / 11（及 Windows Server 2016+）。
- **Linux (x86_64)** — glibc ≥ 2.31 的发行版（Ubuntu 20.04+ / Debian 11+ /
  RHEL 9 / Rocky 9 / Alma 9+）。FrankenPHP 与 Redis 为 musl 完全静态构建，
  MariaDB 以 glibc 2.31 为基线且不依赖 libaio。
- **Docker** — 任意 Docker 引擎；镜像基于 `debian:bookworm-slim`。

## 安装包校验 / Verify Installers

```powershell
# Windows
Get-FileHash frampp-setup-<channel>-<version>-windows-x64.exe -Algorithm SHA256

# Linux
sha256sum frampp-setup-<channel>-<version>-linux-x86_64.run
```

与 GitHub Releases 中的 `SHA256SUMS.txt` 对应行比对。
Compare against the matching line in `SHA256SUMS.txt` on the GitHub Release.

## 端口 / Ports

| 端口 / Port | 服务 / Service |
| --- | --- |
| 8080 | 默认站点 / default site |
| 8081 | 控制面板 / control panel |
| 3306 | MariaDB |
| 6379 | Redis |

## 安全基线 / Security Baseline

- 服务仅绑定 `127.0.0.1`；数据库与 Redis 不向外部暴露。
- 首次安装生成随机 MariaDB root 密码、只读账号 `frampp_ro`、Redis 密码与面板令牌。
- 控制面板（`http://127.0.0.1:8081/`）的变更操作需要面板令牌。

## 内部传输模式 / Internal Transport Mode

默认使用 TCP 端口（Caddy admin `127.0.0.1:2019`、MariaDB 3306、Redis 6379），
可用管理工具直接连接数据库。若你更关注安全性与端口冲突（如同机多实例），
可切换到 unix socket 模式（**仅 Linux**）：

```bash
bin/frampp mode sock     # 切换到 unix socket（admin / mysql / redis 走 var/run/*.sock）
bin/frampp mode tcp      # 切回 TCP
bin/frampp mode status   # 查看当前模式与各组件地址
source bin/env           # sock 模式下 mysql 客户端自动走 socket
redis-cli -s var/run/redis.sock   # Redis 客户端连接 socket
```

sock 模式不影响对外站点端口（8080/8081 仍在 Caddyfile 中配置）。
Windows 不支持 unix socket，切换脚本会提示并保持 TCP。
