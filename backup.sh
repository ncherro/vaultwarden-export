#!/bin/sh
set -e

# Helper function to get secret from env var or file
get_secret() {
  var_name="$1"
  file_var_name="${var_name}_FILE"

  # Check if file path is provided
  eval file_path="\$$file_var_name"
  if [ -n "$file_path" ] && [ -f "$file_path" ]; then
    cat "$file_path"
    return
  fi

  # Fall back to direct env var
  eval value="\$$var_name"
  if [ -n "$value" ]; then
    echo "$value"
    return
  fi

  echo "Error: $var_name or $file_var_name must be set" >&2
  return 1
}

# Process RCLONE_CONFIG_*_FILE env vars
# Reads file contents and exports as RCLONE_CONFIG_* for rclone to use
load_rclone_secrets() {
  for var_name in $(env | grep '^RCLONE_CONFIG_.*_FILE=' | cut -d= -f1); do
    eval file_path="\$$var_name"
    # Strip _FILE suffix to get the target var name
    target_var="${var_name%_FILE}"
    if [ -f "$file_path" ]; then
      value=$(cat "$file_path")
      export "$target_var=$value"
      echo "  Loaded $target_var from file"
    else
      echo "Warning: File not found for $var_name: $file_path" >&2
    fi
  done
}

# Cleanup function
cleanup() {
  rm -f /tmp/vault.json
  bw logout 2>/dev/null || true
}
trap cleanup EXIT

# Load secrets
echo "Loading secrets..."
export BW_CLIENTID=$(get_secret BW_CLIENTID)
export BW_CLIENTSECRET=$(get_secret BW_CLIENTSECRET)
BW_MASTER_PASSWORD=$(get_secret BW_MASTER_PASSWORD)
BACKUP_PASSWORD=$(get_secret BACKUP_PASSWORD)

# Load rclone secrets from files
load_rclone_secrets

# Validate required config
if [ -z "$BW_URL" ]; then
  echo "Error: BW_URL must be set" >&2
  exit 1
fi

if [ -z "$RCLONE_DEST" ]; then
  echo "Error: RCLONE_DEST must be set (e.g., s3:bucket/path)" >&2
  exit 1
fi

# Configuration
RETENTION_COUNT="${RETENTION_COUNT:-7}"
BACKUP_FILENAME="${BACKUP_FILENAME:-vaultwarden-%Y-%m-%d.json}"
DATE_FILENAME=$(date +"$BACKUP_FILENAME")

echo "Starting Vaultwarden backup..."
echo "  Server: $BW_URL"
echo "  Destination: $RCLONE_DEST"
echo "  Filename: $DATE_FILENAME"

# Configure and login to Bitwarden
echo "Configuring Bitwarden CLI..."
bw config server "$BW_URL"

echo "Logging in..."
bw login --apikey

echo "Unlocking vault..."
BW_SESSION=$(echo "$BW_MASTER_PASSWORD" | bw unlock --raw)
export BW_SESSION

# Export vault
echo "Exporting vault..."
bw export --format encrypted_json --password "$BACKUP_PASSWORD" --output /tmp/vault.json

# Verify export exists and has content
if [ ! -s /tmp/vault.json ]; then
  echo "Error: Export file is empty or missing" >&2
  exit 1
fi

# Upload to destination
echo "Uploading to $RCLONE_DEST..."
if ! rclone copyto /tmp/vault.json "$RCLONE_DEST/$DATE_FILENAME"; then
  echo "Error: Upload failed" >&2
  exit 1
fi

echo "Upload complete."

# Retention: keep only the last N backups
if [ "$RETENTION_COUNT" -gt 0 ]; then
  echo "Applying retention policy (keeping $RETENTION_COUNT backups)..."

  # List files, sort by name (date), skip the newest N, delete the rest
  rclone lsf "$RCLONE_DEST" --files-only 2>/dev/null | \
    grep -E '^vaultwarden-.*\.json$' | \
    sort -r | \
    tail -n +$((RETENTION_COUNT + 1)) | \
    while read -r file; do
      echo "  Deleting old backup: $file"
      rclone deletefile "$RCLONE_DEST/$file" || true
    done
fi

echo "Backup completed successfully at $(date)"
