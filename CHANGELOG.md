# Changelog

All notable changes to FRAMPP are documented here.

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
