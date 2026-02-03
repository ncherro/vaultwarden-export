#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Smoke Test ==="
echo "Building Docker image..."
docker build -t vaultwarden-export-test "$PROJECT_DIR"

echo ""
echo "Running container with mocked commands..."
docker run --rm \
  -e BW_URL=https://vault.example.com \
  -e BW_CLIENTID=test-client-id \
  -e BW_CLIENTSECRET=test-client-secret \
  -e BW_MASTER_PASSWORD=test-master-password \
  -e BACKUP_PASSWORD=test-backup-password \
  -e RCLONE_DEST=/backups \
  -e RUN_ONCE=true \
  -e RETENTION_COUNT=2 \
  -e PATH=/mocks:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -v "$SCRIPT_DIR/mocks:/mocks:ro" \
  -v /tmp/vaultwarden-export-test:/backups \
  vaultwarden-export-test

echo ""
echo "=== Smoke Test Passed ==="
