# Vaultwarden Export

[![CI](https://github.com/ncherro/vaultwarden-export/actions/workflows/ci.yml/badge.svg)](https://github.com/ncherro/vaultwarden-export/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/ncherro/vaultwarden-export?sort=semver)](https://github.com/ncherro/vaultwarden-export/pkgs/container/vaultwarden-export)

Automated encrypted exports for [Vaultwarden](https://github.com/dani-garcia/vaultwarden) using the official [Bitwarden CLI](https://bitwarden.com/help/cli/).

## Why This Approach?

Most Vaultwarden backup solutions copy the SQLite database directly. This has drawbacks:

- Must handle WAL files and database locks correctly
- Tied to Vaultwarden's internal schema (version-dependent)
- Cannot easily restore to a different Bitwarden-compatible server

This tool uses the **Bitwarden CLI** to create a proper encrypted export:

- Portable, password-protected JSON export
- Can restore to Vaultwarden, official Bitwarden, or any compatible server
- Decoupled from internal database format
- Uses [rclone](https://rclone.org/) for 40+ storage backends

## Quick Start

```yaml
# docker-compose.yml
services:
  vaultwarden-export:
    image: ghcr.io/ncherro/vaultwarden-export:latest
    restart: unless-stopped
    environment:
      - BW_URL=https://vault.example.com
      - RCLONE_DEST=s3:my-bucket/backups
      - RCLONE_CONFIG_S3_TYPE=s3
      - RCLONE_CONFIG_S3_PROVIDER=AWS
      - RCLONE_CONFIG_S3_ACCESS_KEY_ID=xxx
      - RCLONE_CONFIG_S3_SECRET_ACCESS_KEY=xxx
      - RCLONE_CONFIG_S3_REGION=us-east-1
      - BW_CLIENTID=user.xxx
      - BW_CLIENTSECRET=xxx
      - BW_MASTER_PASSWORD=xxx
      - BACKUP_PASSWORD=xxx
```

```bash
docker-compose up -d
```

## Configuration

### Required

| Variable | Description |
|----------|-------------|
| `BW_URL` | Your Vaultwarden server URL |
| `BW_CLIENTID` | Bitwarden API client ID |
| `BW_CLIENTSECRET` | Bitwarden API client secret |
| `BW_MASTER_PASSWORD` | Master password to unlock the vault |
| `BACKUP_PASSWORD` | Password to encrypt the backup file |
| `RCLONE_DEST` | Rclone destination (e.g., `s3:bucket/path`) |
| `RCLONE_CONFIG_*` | Rclone backend config (see [Storage Backends](#storage-backends)) |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_CRON` | `0 4 * * *` | Cron schedule (daily at 4am) |
| `RUN_ONCE` | `false` | Run once and exit (for K8s jobs) |
| `BACKUP_ON_START` | `false` | Run backup on container start |
| `RETENTION_COUNT` | `7` | Backups to keep (0 = unlimited) |
| `BACKUP_FILENAME` | `vaultwarden-%Y-%m-%d.json` | Filename pattern |
| `TZ` | `UTC` | Timezone for cron |

### File-Based Secrets

For better security, use file-based secrets instead of environment variables. Environment variables can leak through process listings, debug logs, and container inspection. File-based secrets avoid this by reading values from files at runtime.

Append `_FILE` to any secret variable:

```yaml
environment:
  # Bitwarden secrets
  - BW_CLIENTID_FILE=/secrets/client_id
  - BW_CLIENTSECRET_FILE=/secrets/client_secret
  - BW_MASTER_PASSWORD_FILE=/secrets/master_password
  - BACKUP_PASSWORD_FILE=/secrets/backup_password
  # Rclone secrets (any RCLONE_CONFIG_* var supports _FILE)
  - RCLONE_CONFIG_S3_ACCESS_KEY_ID_FILE=/secrets/aws_access_key_id
  - RCLONE_CONFIG_S3_SECRET_ACCESS_KEY_FILE=/secrets/aws_secret_access_key
volumes:
  - ./secrets:/secrets:ro
```

Restrict file permissions so only the owner can read them:

```bash
chmod 600 secrets/*
```

The `_FILE` suffix works with all secret variables (`BW_CLIENTID`, `BW_CLIENTSECRET`, `BW_MASTER_PASSWORD`, `BACKUP_PASSWORD`) and any `RCLONE_CONFIG_*` variable.

## Getting Bitwarden API Credentials

1. Log into your Vaultwarden web UI
2. Go to **Settings** → **Security** → **Keys**
3. Click **View API Key**
4. Copy the `client_id` and `client_secret`

## Storage Backends

Uses [rclone](https://rclone.org/) for uploads, supporting 40+ providers.

### Amazon S3

```yaml
environment:
  - RCLONE_DEST=s3:my-bucket/vaultwarden
  - RCLONE_CONFIG_S3_TYPE=s3
  - RCLONE_CONFIG_S3_PROVIDER=AWS
  - RCLONE_CONFIG_S3_ACCESS_KEY_ID=xxx
  - RCLONE_CONFIG_S3_SECRET_ACCESS_KEY=xxx
  - RCLONE_CONFIG_S3_REGION=us-east-1
```

### Backblaze B2

```yaml
environment:
  - RCLONE_DEST=b2:my-bucket/vaultwarden
  - RCLONE_CONFIG_B2_TYPE=b2
  - RCLONE_CONFIG_B2_ACCOUNT=xxx
  - RCLONE_CONFIG_B2_KEY=xxx
```

### Local Directory

```yaml
environment:
  - RCLONE_DEST=/backups
volumes:
  - /path/on/host:/backups
```

### Using rclone.conf

```yaml
environment:
  - RCLONE_CONFIG=/config/rclone.conf
  - RCLONE_DEST=myremote:bucket/path
volumes:
  - ./rclone.conf:/config/rclone.conf:ro
```

## Restore

1. Log into your Vaultwarden web UI
2. Go to **Tools** → **Import Data**
3. Select format: **Bitwarden (json)**
4. Upload your backup file
5. Enter the backup password when prompted

## Manual Backup

```bash
docker run --rm \
  -e BW_URL=https://vault.example.com \
  -e RCLONE_DEST=/backups \
  -e BW_CLIENTID=xxx \
  -e BW_CLIENTSECRET=xxx \
  -e BW_MASTER_PASSWORD=xxx \
  -e BACKUP_PASSWORD=xxx \
  -e RUN_ONCE=true \
  -v /path/to/backups:/backups \
  ghcr.io/ncherro/vaultwarden-export:latest
```

## Building

```bash
docker build -t vaultwarden-export .
```

## Security Considerations

- **Backup password**: Use a strong, unique password stored separately from your master password
- **File-based secrets**: Preferred over environment variables for production
- **Master password exposure**: This tool requires your master password - consider the implications for your threat model

## Issues

Found a bug or have a feature request? [Open an issue](https://github.com/ncherro/vaultwarden-export/issues) on GitHub.

## Disclaimer

This tool requires access to your Vaultwarden master password. Use at your own risk. The authors are not responsible for data loss or security incidents.

## License

MIT
