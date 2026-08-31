# Changelog

All notable changes to FRAMPP are documented here.

## [0.7.1] - 2026-09-01

### Added

- Linux install root now ships a LAMPP-style master command: `frampp` is a
  symbolic link to `bin/frampp`, so `./frampp start|stop|status` works
  directly from the installation directory. The link is created at packaging
  time (`installer/scripts/build-linux-package.ps1`) and `init.sh` recreates
  it as a fallback when missing (e.g. manual copies).

### Changed

- Bumped FRAMPP version to `0.7.1`.

## [0.7.0] - 2026-08-31

### Added

- Linux x86_64 database component is now **MySQL 8.0.46 Community** trimmed
  from the official glibc 2.17 minimal tarball
  (`installer/scripts/linux/trim-mysql.sh`). The official build targets
  CentOS 7 (glibc ≥ 2.17), bundles OpenSSL (and Kerberos / LDAP / SASL) in
  `lib/private`, and has no systemd dependency, so the same binary runs on
  CentOS 7 and modern distributions; the server only requires `libaio`.
  Unused components are removed to keep the module compact: `lib/mecab`
  dictionaries (~129 MB), Kerberos / LDAP-SASL / OCI / FIDO authentication
  plugins, group replication, sample/test plugins, non-core CLI tools,
  headers, docs and localized error messages except English.
- Database init now uses `mysqld --initialize-insecure` plus PHP PDO
  (mysqlnd) over a unix socket to create accounts — no dependency on the
  `mysql` CLI (which may need `libtinfo.so.5` on newer Debian/Ubuntu).
  Secrets are stored as `mysql_root_password` / `mysql_readonly_password`
  (upgraded runtimes get the new keys added automatically).
- Simplified installer naming from `frampp-setup-<channel>-<version>-<env>`
  to **`frampp-<version>-<env>.<ext>`** (`frampp-0.7.0-linux-x86_64.run`,
  `frampp-0.7.0-windows-x64.exe`); the component channel is documented in
  the release notes.
- The Linux install package no longer contains an `installer/` directory:
  runtime scripts moved to `bin/` (init / docker-entrypoint /
  docker-healthcheck), config templates and the systemd unit template moved
  to `share/templates/`, and the version manifest to `share/`.

### Changed

- The Linux service shown by `frampp status` / control panel is now
  **`mysql`** (`modules/mysql`, datadir `var/mysql`, logs `mysql.log` /
  `mysql.err.log`); Windows keeps `mariadb` for now and switches in a later
  milestone.
- Linux runtime dependency baseline: the MySQL module requires glibc
  ≥ 2.17 (CentOS 7 compatible) and `libaio`; the Docker image installs
  `libaio1` / `libnuma1`.
- Agent MySQL tools read `mysql_readonly_password` with fallback to the old
  `mariadb_readonly_password`; log tools accept both `mysql` and `mariadb`
  service names.
- CI smoke test asserts MySQL GLIBC ≤ 2.17 and verifies the database through
  PHP PDO (the same path the control panel uses).
- Bumped FRAMPP version to `0.7.0`.

### Notes

- MySQL 8.0 reached end of life on 2026-04-30 (8.0.46 is the final release);
  it is adopted as the CentOS 7-compatible baseline. A dual-variant switch to
  MySQL 8.4 LTS / MariaDB 11.4 for modern distributions is planned next.
- **MariaDB data directories are not compatible with MySQL 8.0.** Upgrading
  from 0.6.0 requires rebuilding the database (see `docs/user/upgrade.md`).
- FRAMPP-created accounts use `mysql_native_password` for broad client
  compatibility over localhost TCP (PHP mysqlnd / Adminer / CLI); MySQL 8.0
  still supports it (8.4 disables it by default — relevant to the future
  dual-variant switch).

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
