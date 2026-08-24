# Changelog

All notable changes to FRAMPP are documented here.

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
