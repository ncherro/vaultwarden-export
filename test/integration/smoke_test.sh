#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORG_ID=00000000-0000-0000-0000-000000000000

echo "=== Smoke Test ==="
echo "Building Docker image..."
docker build -t vaultwarden-export-test "$PROJECT_DIR"

# Run the container with mocked commands; extra args are passed to docker run
run_backup() {
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
    "$@" \
    vaultwarden-export-test
}

echo ""
echo "--- Test 1: user vault export ---"
OUTPUT=$(run_backup)
echo "$OUTPUT"
if echo "$OUTPUT" | grep -q -- "--organizationid"; then
  echo "Test 1 failed: user vault export should not pass --organizationid" >&2
  exit 1
fi
echo "Test 1 passed."

echo ""
echo "--- Test 2: organization vault export ---"
OUTPUT=$(run_backup -e ORG_ID="$ORG_ID")
echo "$OUTPUT"
if ! echo "$OUTPUT" | grep -q -- "--organizationid $ORG_ID"; then
  echo "Test 2 failed: expected bw export to receive --organizationid $ORG_ID" >&2
  exit 1
fi
echo "Test 2 passed."

echo ""
echo "=== Smoke Test Passed ==="
