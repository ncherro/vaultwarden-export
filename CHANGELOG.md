# Changelog

All notable changes to this project are documented here. Versions match the
[GitHub releases](https://github.com/ncherro/vaultwarden-export/releases) and
the `ghcr.io/ncherro/vaultwarden-export` image tags.

## [Unreleased]

### Added

- Multi-platform images: `linux/arm64` and `linux/arm/v7` are now published
  alongside `linux/amd64`.
- The integration smoke test also runs on a native arm64 runner in CI.

### Changed

- Base image updated from Alpine 3.19 to Alpine 3.24 (Node.js 24, rclone
  1.74.1). The newer rclone includes backends missing from 1.65, such as Filen.
- Bitwarden CLI updated from 2024.9.0 to 2026.9.0. The new CLI no longer needs
  the native `argon2` module, which is what previously blocked ARM builds.
  **If you run an older Vaultwarden server, test a backup after upgrading**, or
  stay on the `0.1` image tag until you can.
- The image is roughly 100 MB larger uncompressed because of the newer Node.js,
  rclone and Bitwarden CLI.

## [0.1.2] - 2026-09-25

### Added

- Organization vault export: set `ORG_ID` to export an organization vault
  instead of the user vault (#1, thanks @nopalpite).

## [0.1.1] - 2026-02-04

### Added

- Webhook notifications on backup success or failure.

## [0.1.0] - 2026-02-03

First versioned release.

- Encrypted exports (`encrypted_json`) using the official Bitwarden CLI.
- Upload to any rclone destination via `RCLONE_DEST` and `RCLONE_CONFIG_*`.
- Cron scheduling, run-once mode and backup-on-start.
- Retention policy (`RETENTION_COUNT`).
- `_FILE` variants for secrets.

[Unreleased]: https://github.com/ncherro/vaultwarden-export/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/ncherro/vaultwarden-export/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ncherro/vaultwarden-export/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ncherro/vaultwarden-export/releases/tag/v0.1.0
