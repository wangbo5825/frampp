# FRAMPP

**FRAMPP = FrankenPHP + Redis + Agent (MCP) + MySQL + PHP + Python**

**One-click, out-of-the-box runtime & development platform for modern PHP developers — following the LAMPP / XAMPP / NMPP tradition, with a built-in AI Agent layer (MCP).**

[中文](README.zh-CN.md) · [Blueprint](docs/blueprint.md) ·
[Releases](https://github.com/wangbo5825/frampp/releases)

> Current status: **v0.6.0** — standardized layout (`bin` / `etc` / `var` /
> `modules`), unified command wrappers, systemd integration, IP access control
> and an all-in-one Docker image.
> Full design & decision records: [docs/blueprint.md](docs/blueprint.md).

[![GitHub](https://img.shields.io/badge/GitHub-wangbo5825%2Fframpp-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/wangbo5825/frampp)
[![Gitee](https://img.shields.io/badge/Gitee-wang_bo_wang_bo%2Fframpp-C71D23?style=flat-square)](https://gitee.com/wang_bo_wang_bo/frampp)
[![License](https://img.shields.io/badge/License-MIT-22d3ee?style=flat-square)](LICENSE)

---

### What is FRAMPP?

FRAMPP bundles the complete web-development stack — PHP application server, MariaDB and Redis — into self-contained, XAMPP-style installers. Download an installer, run it, and start developing within minutes.

We focus on **everyday developers who want a zero-friction local environment**, not power users who need multiple PHP versions running side by side (Laragon / Herd style). Like XAMPP, FRAMPP publishes a different one-click installer for each FRAMPP version × component channel × environment.

Key characteristics:

- **Self-contained** — FrankenPHP (embedded Caddy, automatic HTTPS, worker mode, built-in APCu / redis / mysqli extensions), MariaDB and Redis are all bundled; no system package manager dependencies.
- **Self-contained and relocatable** — Linux installs under `~/frampp` by default without root; Windows uses an Inno Setup installer.
- **Docker-ready** — the same stack ships as a single public Docker image for `docker run` / Docker Compose one-click startup.
- **Standard layout & commands** — `bin/` for commands, `etc/` for configs,
  `var/` for runtime data, `modules/` for components; the directory is
  relocatable and `bin/frampp init` re-initializes after moving.
- **One-command management** — `frampp {status|start|stop|cleanup|logs|new-project|ip-access}` plus a web control panel (services, IP access control, site manager).
- **AI-ready** — a built-in Agent (MCP) layer lets AI assistants interact with your local stack through standard MCP tools.
- **Secure by default** — services bind to localhost, runtime secrets are generated per installation, read-only database accounts are used where applicable, and audit logs are kept.
- **Separate bilingual docs** — English and Chinese root README / changelog files.

### Components

| Letter | Component | Role |
| --- | --- | --- |
| F | FrankenPHP | Application server — embedded Caddy, automatic HTTPS, worker mode |
| R | Redis | Cache / queue / sessions |
| A | Agent | MCP server — the tool layer that connects AI agents to your stack |
| M | MySQL / MariaDB | Relational database (MariaDB by default) |
| P | PHP | Primary language |
| P | Python | Supporting language — automation and AI workloads (optional, embedded lightweight runtime) |

### Quick Start

#### Windows

```powershell
# Download frampp-setup-8.5-0.6.0-windows-x64.exe from GitHub Releases,
# then double-click to install; the installer initializes and starts the stack automatically.

# Dev preview (run from source)
powershell -ExecutionPolicy Bypass -File installer/scripts/download.ps1   # fetch & verify components
powershell -ExecutionPolicy Bypass -File installer/scripts/init.ps1       # init runtime
php control-panel/bin/frampp start all                                    # start
php control-panel/bin/frampp status                                       # status
php control-panel/bin/frampp stop all                                     # stop
```

#### Linux (x86_64, one-click installer)

```bash
# Download frampp-setup-8.5-0.6.0-linux-x86_64.run from GitHub Releases
chmod +x frampp-setup-8.5-0.6.0-linux-x86_64.run
./frampp-setup-8.5-0.6.0-linux-x86_64.run                              # installs to ~/frampp
./frampp-setup-8.5-0.6.0-linux-x86_64.run --prefix /opt/frampp         # custom directory
```

The installer verifies package integrity, extracts the bundle, initializes the runtime (random secrets, MariaDB data directory) and starts all services, then prints the URLs.

After install, visit:

- Default site: <http://127.0.0.1:8080/>
- Control panel: <http://127.0.0.1:8081/> — services, IP access control and a site manager (`sites.php`) for PHP / static / reverse-proxy sites with hot reload.
- Manage: `~/frampp/bin/frampp {status|start|stop|cleanup|logs|new-project|ip-access}`
- Standard commands: `bin/php`, `bin/composer`, `bin/python`, `bin/pip`,
  `bin/mysql`, `bin/redis-cli`; `source bin/env` sets `PATH` / `PHPRC`.
- systemd: `sudo bin/install-systemd` installs a boot service.

The Linux package bundles a slimmed, mostly static FrankenPHP (APCu / redis /
mysqli built in), a source-built MariaDB, statically compiled Redis, and a
pruned embedded Python 3.13 runtime — no system packages required; the directory
is relocatable (run `bin/frampp init` after moving).

#### Docker

The same self-contained stack is published as a single public Docker image, so
you can start it without installing any components:

```bash
docker run -d --name frampp \
  -p 8080:8080 -p 8081:8081 \
  -v frampp-data:/opt/frampp/var \
  -v frampp-logs:/opt/frampp/logs \
  -v frampp-htdocs:/opt/frampp/htdocs \
  ghcr.io/wangbo5825/frampp:0.6.0
```

Or use Docker Compose from the repository:

```bash
docker compose up -d
```

The first container start initializes the runtime (random secrets, MariaDB data
directory and generated configs), then starts FrankenPHP, MariaDB and Redis.
Visit the default site at <http://127.0.0.1:8080/> and the control panel at
<http://127.0.0.1:8081/>. See [docs/user/docker.md](docs/user/docker.md) for
volumes, ports and build-from-source details.

### Releases

Like XAMPP, installers are published per FRAMPP version × component channel × environment:

- Windows: `frampp-setup-8.5-<version>-windows-x64.exe`
- Linux: `frampp-setup-8.5-<version>-linux-x86_64.run`
- Docker: `ghcr.io/wangbo5825/frampp:<version>` (single all-in-one image)

Download & verify: [GitHub Releases](https://github.com/wangbo5825/frampp/releases) · Release process: [docs/releases.md](docs/releases.md).

### System Requirements

- **Windows** — x64, Windows 10 / 11 (and Windows Server 2016+).
- **Linux (x86_64)** — any glibc ≥ 2.31 distribution (Ubuntu 20.04+, Debian 11+,
  RHEL 9 / Rocky 9 / Alma 9+). FrankenPHP and Redis are fully static musl
  binaries (no glibc dependency), and MariaDB is compiled against a glibc 2.31
  baseline without libaio.
- **Docker** — any host with a Docker engine; the image is based on
  `debian:bookworm-slim`.

CI enforces this portability in the smoke test (`PORTABLE_OK`: FrankenPHP static
 MariaDB GLIBC ≤ 2.31). See [docs/releases.md](docs/releases.md).

### Documentation

- Project site (EN/ZH toggle): <https://wangbo5825.github.io/frampp/>
- GitHub (primary): <https://github.com/wangbo5825/frampp>
- Gitee (mirror for China): <https://gitee.com/wang_bo_wang_bo/frampp>
- Dev guide: [AGENTS.md](AGENTS.md)
- Blueprint & milestones: [docs/blueprint.md](docs/blueprint.md)
- Releases: [docs/releases.md](docs/releases.md)
- User docs (shipped with installers): [docs/user/README.md](docs/user/README.md)

### License

[MIT](LICENSE)

---

## 中文

完整中文文档见 [README.zh-CN.md](README.zh-CN.md)。
