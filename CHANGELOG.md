# Changelog

## [0.2.0] - 2025-06-17

### Added

- **Multiple remote destinations**: Upload backups to multiple rclone remotes in a single run, following the same pattern as ttionya/vaultwarden-backup. Configure with `RCLONE_REMOTE_NAME` / `RCLONE_REMOTE_DIR` (primary) and `RCLONE_REMOTE_NAME_1` / `RCLONE_REMOTE_DIR_1`, `RCLONE_REMOTE_NAME_2` / `RCLONE_REMOTE_DIR_2`, etc. for additional destinations.
- **Per-remote retention**: Old backups are pruned independently on each remote based on `RETENTION_COUNT`.
- **Partial failure tolerance**: If one remote fails, the backup continues to the remaining remotes. A summary of OK/failed remotes is reported at the end and via webhook notifications.
- **`RCLONE_CONFIG` environment variable**: Explicitly set the path to the rclone config file (default: `~/.config/rclone/rclone.conf`). Useful when sharing an rclone volume with other containers.
- **`RCLONE_EXTRA_FLAGS` environment variable**: Pass additional flags to rclone commands (default: `--transfers=4 --checkers=8 --contimeout=60s --timeout=300s --retries=3`).
- **Workflow ARM64**: Added support for ARM64 architecture.


### Changed

- **Backup upload logic**: Replaced single `RCLONE_DEST` upload with a multi-remote loop. `RCLONE_DEST` is still supported as a fallback when no `RCLONE_REMOTE_NAME` is configured, but multi-remote mode is now the recommended approach.
- **Upload reporting**: Each remote upload is individually logged with `[OK]` or `[FAIL]` status, followed by a summary line with the total count.
- **Webhook notifications**: On partial failure (some remotes OK, some failed), an error webhook is sent with the details of which remotes failed.
- **Rclone install**: Replaced `curl -fsSL https://rclone.org/install.sh | bash` with `apk add --no-cache rclone`.

### Updated

- **Rclone**: Updated to the latest version (1.74.3).
- **Bitwarden CLI**: Updated to the latest version (2025.2.0).