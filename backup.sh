#!/bin/sh
set -e

# Load shared functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/functions.sh"

# Temp file for export
TEMP_FILE="/tmp/vault.json"
BACKUP_SUCCESS=false

# Send webhook notification
send_webhook() {
  url="$1"
  custom_message="$2"
  default_message="$3"

  if [ -n "$url" ]; then
    if [ -n "$custom_message" ]; then
      # Replace placeholders in custom message
      body=$(echo "$custom_message" | sed \
        -e "s|{message}|$default_message|g" \
        -e "s|{service}|vaultwarden-export|g" \
        -e "s|{timestamp}|$(date -Iseconds)|g")
    else
      # Default JSON payload
      body="{\"service\": \"vaultwarden-export\", \"message\": \"$default_message\", \"timestamp\": \"$(date -Iseconds)\"}"
    fi

    curl -s -X POST "$url" \
      -H "Content-Type: application/json" \
      -d "$body" \
      || echo "Warning: Failed to send webhook notification" >&2
  fi
}

notify_error() {
  send_webhook "$WEBHOOK_ERROR_URL" "$WEBHOOK_ERROR_MESSAGE" "$1"
}

notify_success() {
  send_webhook "$WEBHOOK_SUCCESS_URL" "$WEBHOOK_SUCCESS_MESSAGE" "$1"
}

# Cleanup function
cleanup() {
  exit_code=$?
  rm -f "$TEMP_FILE"
  bw logout 2>/dev/null || true

  # Send failure notification if backup didn't complete successfully
  if [ "$BACKUP_SUCCESS" != "true" ] && [ $exit_code -ne 0 ]; then
    notify_error "Backup failed with exit code $exit_code"
  fi
}
trap cleanup EXIT

# Load secrets
echo "Loading secrets..."
export BW_CLIENTID=$(get_secret BW_CLIENTID) && echo "  Loaded BW_CLIENTID"
export BW_CLIENTSECRET=$(get_secret BW_CLIENTSECRET) && echo "  Loaded BW_CLIENTSECRET"
BW_MASTER_PASSWORD=$(get_secret BW_MASTER_PASSWORD) && echo "  Loaded BW_MASTER_PASSWORD"
BACKUP_PASSWORD=$(get_secret BACKUP_PASSWORD) && echo "  Loaded BACKUP_PASSWORD"

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
# Extract prefix for retention matching
BACKUP_PREFIX=$(get_backup_prefix "$BACKUP_FILENAME")

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
BW_SESSION=$(printf '%s' "$BW_MASTER_PASSWORD" | bw unlock --raw)
export BW_SESSION

# Export vault
echo "Exporting vault..."
bw export --format encrypted_json --password "$BACKUP_PASSWORD" --output "$TEMP_FILE"

# Verify export exists and has content
if [ ! -s "$TEMP_FILE" ]; then
  echo "Error: Export file is empty or missing" >&2
  exit 1
fi

# Upload to destination
echo "Uploading to $RCLONE_DEST..."
if ! rclone copyto "$TEMP_FILE" "$RCLONE_DEST/$DATE_FILENAME"; then
  echo "Error: Upload failed" >&2
  exit 1
fi

echo "Upload complete."

# Retention: keep only the last N backups
if [ "$RETENTION_COUNT" -gt 0 ]; then
  echo "Applying retention policy (keeping $RETENTION_COUNT backups)..."

  # List files matching prefix, sort by name (date), skip the newest N, delete the rest
  rclone lsf "$RCLONE_DEST" --files-only 2>/dev/null | \
    grep "^${BACKUP_PREFIX}" | \
    sort -r | \
    tail -n +$((RETENTION_COUNT + 1)) | \
    while read -r file; do
      echo "  Deleting old backup: $file"
      rclone deletefile "$RCLONE_DEST/$file" || true
    done
fi

BACKUP_SUCCESS=true
echo "Backup completed successfully at $(date)"
notify_success "Backup completed successfully"
