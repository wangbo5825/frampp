# FRAMPP

**FRAMPP = FrankenPHP + Redis + Agent (MCP) + MySQL + PHP + Python**

**One-click, out-of-the-box runtime & development platform for modern PHP developers — following the LAMPP / XAMPP / NMPP tradition, with a built-in AI Agent layer (MCP).**

[中文](README.zh-CN.md) · [Blueprint](docs/blueprint.md) ·
[Releases](https://github.com/wangbo5825/frampp/releases)

> Current status: **v0.8.4 compatibility update** — **PHP 8.5.12** and
> **FrankenPHP 1.13.2** retain the critical PHP2Shell fixes
> (CVE-2026-109618 / CVE-2026-109619) and four FrankenPHP security fixes.
> Windows x64, Linux x86_64/aarch64 installers and the multi-arch Docker image
> all use this security baseline. The `apps/<app>/{htdocs,config,src,var}`
> layout and English-first installer messages remain available. The Linux
> x86_64 build now targets the documented `x86-64-v2` CPU baseline, and
> pogo_scheduler v0.2.0 supports multiple independent jobs.
> Full design & decision records: [docs/blueprint.md](docs/blueprint.md).

[![GitHub](https://img.shields.io/badge/GitHub-wangbo5825%2Fframpp-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/wangbo5825/frampp)
[![Gitee](https://img.shields.io/badge/Gitee-wang_bo_wang_bo%2Fframpp-C71D23?style=flat-square)](https://gitee.com/wang_bo_wang_bo/frampp)
[![License](https://img.shields.io/badge/License-MIT-22d3ee?style=flat-square)](LICENSE)

---

### What is FRAMPP?

FRAMPP bundles the complete web-development stack — PHP application server, MySQL / MariaDB and Redis — into self-contained, XAMPP-style installers. Download an installer, run it, and start developing within minutes.

We focus on **everyday developers who want a zero-friction local environment**, not power users who need multiple PHP versions running side by side (Laragon / Herd style). Like XAMPP, FRAMPP publishes a different one-click installer for each FRAMPP version × component channel × environment.

Key characteristics:

- **Self-contained** — FrankenPHP (embedded Caddy, automatic HTTPS, worker mode, built-in APCu / redis / mysqli extensions), MySQL 8.0 (Linux) / MariaDB (Windows) and Redis are all bundled; no system package manager dependencies.
- **Self-contained and relocatable** — Linux installs under `~/frampp` by default without root; Windows uses an Inno Setup installer.
- **Docker-ready** — the same stack ships as a single public Docker image for `docker run` / Docker Compose one-click startup.
- **Standard layout & commands** — `bin/` for commands, `etc/` for configs,
  `var/` for runtime data, `modules/` for components; the directory is
  relocatable and `bin/frampp init` re-initializes after moving.
- **One-command management** — `frampp {status|start|stop|restart|cleanup|mode|logs|new-project|ip-access}` plus a web console (services & IP access control) and the caddy-panel Caddy management UI at `http://127.0.0.1:8081/panel` (sites, Caddyfile, certificates, logs, snapshots).
- **AI-ready** — a built-in Agent (MCP) layer lets AI assistants interact with your local stack through standard MCP tools.
- **Secure by default** — services bind to localhost, runtime secrets are generated per installation, read-only database accounts are used where applicable, and audit logs are kept.
- **Separate bilingual docs** — English and Chinese root README / changelog files.

### Components

| Letter | Component | Role |
| --- | --- | --- |
| F | FrankenPHP | Application server — embedded Caddy, automatic HTTPS, worker mode |
| R | Redis | Cache / queue / sessions |
| A | Agent | MCP server — the tool layer that connects AI agents to your stack |
| M | MySQL / MariaDB | Relational database (MySQL 8.0 on Linux; MariaDB on Windows) |
| P | PHP | Primary language |
| P | Python | Supporting language — automation and AI workloads (optional, embedded lightweight runtime) |

### Quick Start

#### Windows

```powershell
# Download frampp-0.8.4-windows-x64.exe from GitHub Releases,
# then double-click to install; the installer initializes and starts the stack automatically.

# Dev preview (run from source)
powershell -ExecutionPolicy Bypass -File installer/scripts/download.ps1   # fetch & verify components
powershell -ExecutionPolicy Bypass -File installer/scripts/init.ps1       # init runtime
php control-panel/bin/frampp start all                                    # start
php control-panel/bin/frampp status                                       # status
php control-panel/bin/frampp stop all                                     # stop
```

#### Linux (x86_64 / aarch64, one-click installer)

```bash
# Download frampp-0.8.4-linux-x86_64.run from GitHub Releases
chmod +x frampp-0.8.4-linux-x86_64.run
./frampp-0.8.4-linux-x86_64.run                              # installs to ~/frampp
./frampp-0.8.4-linux-x86_64.run --prefix /opt/frampp         # custom directory

# arm64 (aarch64) hosts: download frampp-0.8.4-linux-aarch64.run instead
chmod +x frampp-0.8.4-linux-aarch64.run
./frampp-0.8.4-linux-aarch64.run --prefix /opt/frampp
```

The installer verifies package integrity, extracts the bundle, initializes the runtime (random secrets, MySQL data directory) and starts all services, then prints the URLs.

0.8.4 keeps the PHP 8.5.12 / FrankenPHP 1.13.2 security baseline and fixes
Linux x86_64 portability by pinning the `x86-64-v2` ISA baseline. The Linux
build now runs a Sandy Bridge CPU compatibility check in CI. The default site
is `apps/default/htdocs`; `frampp new-project` creates
`apps/<name>/{htdocs,config,src,var}`. Optional Linux scheduling is configured
in `etc/scheduler.caddy` using multiple independent `job` blocks, and older
`htdocs/` content is migrated by `init`.

After install, visit:

- Default site: <http://127.0.0.1:8080/>
- Control panel: <http://127.0.0.1:8081/> — services, IP access control and a site manager (`sites.php`) for PHP / static / reverse-proxy sites with hot reload.
- Manage: `~/frampp/bin/frampp {status|start|stop|restart|cleanup|logs|new-project|ip-access}`
- Standard commands: `bin/php`, `bin/composer`, `bin/python`, `bin/pip`,
  `bin/mysql`, `bin/redis-cli`; `source bin/env` sets `PATH` / `PHPRC`.
- systemd: `sudo bin/install-systemd` installs a boot service.

The Linux package bundles a slimmed, completely static FrankenPHP (APCu / redis /
mysqli built in), a trimmed official MySQL 8.0 (glibc 2.17 on x86_64, glibc 2.28
on aarch64), statically compiled Redis, and a
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
  -v frampp-apps:/opt/frampp/apps \
  -v frampp-htdocs:/opt/frampp/htdocs \
  ghcr.io/wangbo5825/frampp:0.8.4
```

Or use Docker Compose from the repository:

```bash
docker compose up -d
```

The first container start initializes the runtime (random secrets, MySQL data
directory and generated configs), then starts FrankenPHP, MySQL and Redis.
Visit the default site at <http://127.0.0.1:8080/> and the control panel at
<http://127.0.0.1:8081/>. See [docs/user/docker.md](docs/user/docker.md) for
volumes, ports and build-from-source details.

### Releases

Like XAMPP, installers are published per FRAMPP version × component channel × environment:

- Windows: `frampp-<version>-windows-x64.exe`
- Linux: `frampp-<version>-linux-x86_64.run` /
  `frampp-<version>-linux-aarch64.run`
- Docker: `ghcr.io/wangbo5825/frampp:<version>` (single all-in-one image)

Download & verify: [GitHub Releases](https://github.com/wangbo5825/frampp/releases) · Release process: [docs/releases.md](docs/releases.md).

### System Requirements

- **Windows** — x64, Windows 10 / 11 (and Windows Server 2016+).
- **Linux (x86_64)** — any glibc ≥ 2.17 distribution (CentOS 7, Ubuntu 20.04+,
  Debian 11+, RHEL 8+ / Rocky 8+ / Alma 8+). FrankenPHP and Redis are fully
  static musl binaries (no glibc dependency), and MySQL 8.0 is the official
  glibc 2.17 generic build (bundled OpenSSL; the server needs `libaio`).
  The x86_64 build targets **x86-64-v2** (SSE4.2/POPCNT, no AVX2/ADX
  requirement) and is smoke-tested with QEMU's Sandy Bridge CPU model.
- **Docker** — any host with a Docker engine; the image is based on
  `debian:bookworm-slim`.

CI enforces this portability in the smoke test (`PORTABLE_OK`: FrankenPHP static
and MySQL GLIBC ≤ 2.17, plus `CPU_COMPAT_OK` under Sandy Bridge emulation).
See [docs/releases.md](docs/releases.md).

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
