# FRAMPP Docker / Docker 镜像

FRAMPP 提供单个 all-in-one Docker 镜像，内置 FrankenPHP、MariaDB、Redis、
Agent（MCP 服务器）、控制面板与精简 Python 运行时。它复用 Linux x86_64
自包含安装包的同一套组件与运行时布局，让 Docker 用户也能“一键启动”。

FRAMPP publishes a single all-in-one Docker image containing FrankenPHP,
MariaDB, Redis, the Agent (MCP server), the control panel and a slim Python
runtime. It reuses the same component matrix and runtime layout as the Linux
x86_64 self-contained installer.

## 一键启动 / One-Click Start

```bash
docker run -d --name frampp \
  -p 8080:8080 -p 8081:8081 \
  -v frampp-data:/opt/frampp/data \
  -v frampp-logs:/opt/frampp/logs \
  -v frampp-htdocs:/opt/frampp/htdocs \
  ghcr.io/wangbo5825/frampp:0.5.0
```

首次启动会自动初始化运行时：生成随机密钥（`data/secrets.json`）、初始化
MariaDB 数据目录、由模板生成 `php.ini` / `redis.conf` / `Caddyfile`，随后启动
FrankenPHP、MariaDB 与 Redis。

On first start the container initializes the runtime automatically: it generates
random secrets (`data/secrets.json`), initializes the MariaDB data directory,
renders `php.ini` / `redis.conf` / `Caddyfile` from templates, and then starts
FrankenPHP, MariaDB and Redis.

访问 / Visit:

- 默认站点 / Default site: <http://127.0.0.1:8080/>
- 控制面板 / Control panel: <http://127.0.0.1:8081/>
- 管理命令 / Manage: `docker exec frampp /opt/frampp/bin/frampp {status|start|stop|logs|new-project}`

## Docker Compose

仓库根目录的 `docker-compose.yml` 封装了常用端口与命名卷：

```bash
docker compose up -d
docker compose logs -f
docker compose down
```

默认只映射 8080（站点）与 8081（控制面板）。如需从宿主机直连 MariaDB 或
Redis，取消 `docker-compose.yml` 中 3306 / 6379 端口的注释。
若使用本地构建的 `frampp:0.5.0` 镜像，可覆盖镜像名：
`FRAMPP_IMAGE=frampp:0.5.0 docker compose up -d`。

The root `docker-compose.yml` wraps the common ports and named volumes. Only
8080 (site) and 8081 (control panel) are published by default; uncomment 3306 /
6379 if you need host access to MariaDB or Redis.
To use a locally built `frampp:0.5.0` image instead, override the image:
`FRAMPP_IMAGE=frampp:0.5.0 docker compose up -d`.

## 卷 / Volumes

| 容器路径 / Container path | 用途 / Purpose |
| --- | --- |
| `/opt/frampp/data` | MariaDB 数据、Redis AOF、`runtime.json` 与 `secrets.json` |
| `/opt/frampp/logs` | FrankenPHP / MariaDB / Redis / 控制面板日志 |
| `/opt/frampp/htdocs` | 默认站点与 `frampp new-project` 创建的项目 |

建议使用命名卷或宿主机目录挂载上述路径，避免删除容器后丢失数据。挂载
`data/` 后，容器重建时不会重新生成密钥与数据库数据。

Persist the paths above with named volumes or host directories to avoid losing
data when the container is removed. Mounting `data/` preserves secrets and the
database across container re-creation.

## 端口 / Ports

| 端口 / Port | 服务 / Service |
| --- | --- |
| 8080 | FrankenPHP 默认站点 / default site |
| 8081 | 控制面板 / control panel |
| 3306 | MariaDB（默认不映射 / not published by default） |
| 6379 | Redis（默认不映射 / not published by default） |

## 安全基线 / Security Baseline

- 服务进程仅绑定 `127.0.0.1`；容器内部可通过 localhost 互访。
- 每次首次启动生成随机 root 密码、只读账号 `frampp_ro`、Redis 密码与面板令牌。
- 容器以非 root 用户 `frampp` 运行。
- 数据库与 Redis 默认不向宿主机暴露；确需暴露时请配置防火墙 / 访问控制。

- Services bind to `127.0.0.1` inside the container.
- Random root password, read-only `frampp_ro` account, Redis password and panel
  token are generated on first start.
- The container runs as the non-root `frampp` user.
- MariaDB and Redis are not published by default.

## 从源码构建 / Build from Source

镜像复用 Linux `.run` 产物，避免在 Dockerfile 内重复编译组件。先构建安装包，
再构建镜像：

```powershell
# Linux + pwsh 7
pwsh -File installer/scripts/build-linux-package.ps1 -Env linux-x86_64
pwsh -File installer/scripts/build-docker.ps1 -ImageName frampp
```

或直接使用 Docker：

```bash
docker build -t frampp:0.5.0 \
  --build-arg FRAMPP_PACKAGE=dist/installer/frampp-setup-8.5-0.5.0-linux-x86_64.run .
```

构建时通过 `--extract-only` 仅解压载荷，不生成密钥；`data/` 在容器首次启动时
才初始化，保证镜像可安全公开分发。

The image reuses the Linux `.run` artifact instead of recompiling components in
the Dockerfile. During build the payload is extracted with `--extract-only` and
no secrets are baked; `data/` is initialized on first container start, so the
image is safe to distribute publicly.

## 镜像发布 / Publishing

CI 中 `linux-package` 作业生成 `.run` 后，`docker` 作业复用该产物构建镜像、
运行冒烟测试；当推送 `v*` tag 时自动推送到
`ghcr.io/wangbo5825/frampp`（版本 tag 与 `latest`）。

In CI, the `linux-package` job produces the `.run`, and the `docker` job reuses
that artifact to build and smoke-test the image. Pushing a `v*` tag publishes
the image to `ghcr.io/wangbo5825/frampp` with a version tag and `latest`.
