#!/bin/sh
set -e

# Load shared functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/functions.sh"

# Temp file for export
TEMP_FILE="/tmp/vault.json"
BACKUP_SUCCESS=false

# Organization export option
ORG_ID="${ORG_ID:-}"

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

# Build list of destinations from RCLONE_REMOTE_NAME/DIR and RCLONE_REMOTE_NAME_N/DIR_N
# This follows the same pattern as ttionya/vaultwarden-backup: https://github.com/ttionya/vaultwarden-backup/blob/master/docs/multiple-remote-destinations.md
#   Primary: RCLONE_REMOTE_NAME + RCLONE_REMOTE_DIR (defaults: BitwardenBackup + /BitwardenBackup/)
#   Additional: RCLONE_REMOTE_NAME_1 + RCLONE_REMOTE_DIR_1, RCLONE_REMOTE_NAME_2 + RCLONE_REMOTE_DIR_2, etc.
# Sequential numbering must be consecutive; gaps will stop parsing.
REMOTE_NAMES=""
REMOTE_DIRS=""

# Primary destination
_PRIMARY_REMOTE="${RCLONE_REMOTE_NAME:-BitwardenBackup}"
_PRIMARY_DIR="${RCLONE_REMOTE_DIR:-/BitwardenBackup/}"
REMOTE_NAMES="${_PRIMARY_REMOTE}"
REMOTE_DIRS="${_PRIMARY_DIR}"

# Additional destinations (numbered 1, 2, 3, ...)
_N=1
while true; do
  eval "_NAME_VAR=\"RCLONE_REMOTE_NAME_${_N}\""
  eval "_DIR_VAR=\"RCLONE_REMOTE_DIR_${_N}\""
  eval "_NAME_VAL=\"\${$_NAME_VAR}\""
  eval "_DIR_VAL=\"\${$_DIR_VAR}\""

  if [ -z "$_NAME_VAL" ] || [ -z "$_DIR_VAL" ]; then
    break
  fi

  REMOTE_NAMES="${REMOTE_NAMES} ${_NAME_VAL}"
  REMOTE_DIRS="${REMOTE_DIRS} ${_DIR_VAL}"
  _N=$((_N + 1))
done

# Configuration
RETENTION_COUNT="${RETENTION_COUNT:-7}"
BACKUP_FILENAME="${BACKUP_FILENAME:-vaultwarden-%Y-%m-%d.json}"
DATE_FILENAME=$(date +"$BACKUP_FILENAME")
# Extract prefix for retention matching
BACKUP_PREFIX=$(get_backup_prefix "$BACKUP_FILENAME")

# Rclone config
RCLONE_CONFIG_PATH="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
RCLONE_EXTRA_FLAGS="${RCLONE_EXTRA_FLAGS:---transfers=4 --checkers=8 --contimeout=60s --timeout=300s --retries=3}"

echo "Starting Vaultwarden backup..."
echo "  Server: $BW_URL"
echo "  Filename: $DATE_FILENAME"
_i=1
for _remote in $REMOTE_NAMES; do
  _dir=$(echo "$REMOTE_DIRS" | cut -d' ' -f$_i)
  echo "  Destination ${_i}: ${_remote}:${_dir}"
  _i=$((_i + 1))
done

# Configure and login to Bitwarden
echo "Configuring Bitwarden CLI..."
bw config server "$BW_URL"

echo "Logging in..."
bw login --apikey

echo "Unlocking vault..."
BW_SESSION=$(printf '%s' "$BW_MASTER_PASSWORD" | bw unlock --raw)
export BW_SESSION

# Export vault
if [ -n "$ORG_ID" ]; then
  echo "Exporting organization vault ($ORG_ID)..."
  bw export --organizationid "$ORG_ID" --format encrypted_json --password "$BACKUP_PASSWORD" --output "$TEMP_FILE"
else
  echo "Exporting user vault..."
  bw export --format encrypted_json --password "$BACKUP_PASSWORD" --output "$TEMP_FILE"
fi

# Verify export exists and has content
if [ ! -s "$TEMP_FILE" ]; then
  echo "Error: Export file is empty or missing" >&2
  exit 1
fi

# Upload function for a single remote
upload_to_remote() {
  _remote="$1"
  _dir="$2"
  _filename="$3"
  _config="$4"
  _flags="$5"

  _dest="${_remote}:${_dir}"
  echo "  Uploading to ${_dest}${_filename}..."
  if rclone copyto "$TEMP_FILE" "${_dest}${_filename}" --config "$_config" $_flags --log-level WARNING 2>&1; then
    echo "  [OK] ${_filename} -> ${_remote}:${_dir}"
    return 0
  else
    echo "  [FAIL] ${_filename} -> ${_remote}:${_dir}" >&2
    return 1
  fi
}

# Retention function for a single remote
apply_retention() {
  _remote="$1"
  _dir="$2"
  _config="$3"
  _flags="$4"
  _count="$5"
  _prefix="$6"

  if [ "$_count" -le 0 ]; then
    return 0
  fi

  echo "  Pruning old backups on ${_remote}:${_dir} (keeping ${_count})..."
  rclone lsf "${_remote}:${_dir}" --config "$_config" $_flags --files-only 2>/dev/null | \
    grep "^${_prefix}" | \
    sort -r | \
    tail -n +"$((_count + 1))" | \
    while read -r file; do
      echo "    Deleting old backup: $file"
      rclone deletefile "${_remote}:${_dir}${file}" --config "$_config" || true
    done
}

# Upload to all destinations
FAILED=""
OK_REMOTES=""
OK_COUNT=0
_i=1
_TOTAL=$(echo "$REMOTE_NAMES" | wc -w | tr -d ' ')

for _remote in $REMOTE_NAMES; do
  _dir=$(echo "$REMOTE_DIRS" | cut -d' ' -f$_i)
  if upload_to_remote "$_remote" "$_dir" "$DATE_FILENAME" "$RCLONE_CONFIG_PATH" "$RCLONE_EXTRA_FLAGS"; then
    OK_COUNT=$((OK_COUNT + 1))
    OK_REMOTES="${OK_REMOTES} ${_remote}"
  else
    FAILED="${FAILED} ${_remote}"
  fi
  _i=$((_i + 1))
done

echo "Upload summary: ${OK_COUNT}/${_TOTAL} remotes ok"

if [ -n "$FAILED" ]; then
  echo "Warning: Failed remotes:${FAILED}" >&2
fi

# Retention on each remote
_i=1
for _remote in $REMOTE_NAMES; do
  _dir=$(echo "$REMOTE_DIRS" | cut -d' ' -f$_i)
  apply_retention "$_remote" "$_dir" "$RCLONE_CONFIG_PATH" "$RCLONE_EXTRA_FLAGS" "$RETENTION_COUNT" "$BACKUP_PREFIX"
  _i=$((_i + 1))
done

BACKUP_SUCCESS=true
echo "Backup completed successfully at $(date)"

if [ -n "$FAILED" ]; then
  notify_error "Backup completed with errors. OK: ${OK_COUNT}/${_TOTAL} remotes. Failed:${FAILED}"
else
  notify_success "Backup completed successfully"
fi