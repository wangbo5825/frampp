# Changelog

All notable changes to FRAMPP are documented here.

## [0.6.0] - 2026-08-29

### Added

- Unified installed layout: software modules live under `modules/`, configs under
  `etc/`, and runtime data moved from `data/` to `var/`.
- Added unified `bin/` command wrappers: `php` (standard PHP CLI compatible),
  `composer`, `python`, `pip`, `mysql`, `redis-cli`, plus an `env` script that
  sets `PATH` / `FRAMPP_HOME` / `PHPRC`; symlinks on Linux and `.cmd` wrappers
  on Windows.
- Added Linux systemd integration: `etc/frampp.service`, `bin/framppd` and
  `bin/install-systemd` (install/remove service).
- Upgraded `caddy-access-filter` to v1.2.0 with local IP / CIDR / country-code
  rules and GeoIP databases; the control panel now manages IP access control
  (rules, default policy, hot reload).
- Added a site manager to the control panel (`/sites.php`): create, edit and
  delete sites as `etc/caddy.d/*.caddy` fragments, then hot-reload the full
  Caddyfile through the Caddy admin API (`/load`, `text/caddyfile`). Supports
  PHP, static and reverse-proxy sites.
- Added process attribution and orphan cleanup: PID files now record the
  launcher (daemon/CLI) and start time; `frampp status` flags services left
  running by an exited `framppd` daemon as `ORPHAN`, and `frampp cleanup`
  (also available in the control panel) reaps orphaned process trees and
  removes stale PID files. Windows process checks use `Get-Process` instead of
  `tasklist /FI` for broader permission compatibility.
- Added `frampp mode sock|tcp|status`: switch internal transports between
  TCP (default: admin 2019 / MariaDB 3306 / Redis 6379) and unix sockets
  (Linux only; `var/run/*.sock` for admin / MySQL / Redis, avoiding port
  conflicts and improving local security). External site ports stay in the
  Caddyfile. Admin API calls (control panel hot reload / site manager) now go
  through a unified `CaddyAdminClient` supporting TCP and unix sockets;
  `bin/env` exports `MYSQL_UNIX_PORT` in sock mode.
- Added process attribution and orphan cleanup: PID files now record the
  launcher (daemon/CLI) and start time; `frampp status` flags services left
  running by an exited `framppd` daemon as `ORPHAN`, and `frampp cleanup`
  (also available in the control panel) reaps orphaned process trees and
  removes stale PID files. Windows process checks use `Get-Process` instead of
  `tasklist /FI` for broader permission compatibility.
- Added a site manager to the control panel (`/sites.php`): create, edit and
  delete sites as `etc/caddy.d/*.caddy` fragments, then hot-reload the full
  Caddyfile through the Caddy admin API (`/load`, `text/caddyfile`). Supports
  PHP, static and reverse-proxy sites.

### Changed

- Moved the uninstall script to `bin/uninstall`; removed the root-level
  `install.sh` and build scripts that are not needed at runtime. The `.run`
  installer now calls `bin/frampp init` directly.
- Installer messages are bilingual (Chinese + English).
- Bumped FRAMPP version to `0.6.0`.

## [0.5.0] - 2026-08-24

### Added

- Added a single all-in-one Docker image (`Dockerfile`, `docker-compose.yml`)
  reusing the Linux x86_64 `.run` payload, with a non-root runtime user,
  first-start initialization and health checks.
- Added Docker entrypoint / healthcheck scripts and a
  `installer/scripts/build-docker.ps1` helper.
- Added CI Docker build, smoke test and GitHub Container Registry publishing
  for release tags.

### Changed

- Added `--extract-only` to the Linux self-extracting installer and
  `--skip-start` to `install.sh` so the same package can build images without
  baking secrets.
- Rebuilt FrankenPHP as a fully static musl binary (no glibc dependency) and
  compiled MariaDB against a glibc 2.31 baseline without libaio, so the Linux
  package runs on Ubuntu 20.04+, Debian 11+ and RHEL 9 / Rocky 9 / Alma 9+.
- Bumped FRAMPP version to `0.5.0`.

## [0.4.0] - 2026-08-21

### Added

- Integrated `caddy-access-filter` v1.0.0 into the Linux FrankenPHP custom build.
- Added separate English and Chinese root documentation files
  (`README.md`, `README.zh-CN.md`, `CHANGELOG.md`, `CHANGELOG.zh-CN.md`).

### Changed

- Bumped FRAMPP version to `0.4.0`.
- Documented the new Caddy module in the blueprint and release notes.

## [0.3.0] - 2026-08-21

### Changed

- Slimmed the Linux package by building MariaDB from source, building a custom
  FrankenPHP with UPX, and bundling a pruned Python 3.13 runtime.
- Pruned Python `include/`, `share/`, Tcl/Tk native libraries and development
  files while preserving pip.
- Preserved Python symlinks during Linux package assembly.

## [0.2.0] - 2026-08-20

### Added

- Added the Linux x86_64 XAMPP-style `.run` installer.
- Added static Redis builds and Linux runtime initialization scripts.

## [0.1.0] - 2026-08-19

### Added

- Initial Windows runtime: FrankenPHP, MariaDB, Redis, APCu and control panel.
- Agent / MCP server and bilingual project site.
