#!/bin/sh
set -e

# Default values
BACKUP_CRON="${BACKUP_CRON:-0 4 * * *}"
RUN_ONCE="${RUN_ONCE:-false}"

echo "Vaultwarden Backup starting..."

if [ "$RUN_ONCE" = "true" ]; then
  echo "Running backup once..."
  exec /backup.sh
else
  echo "Setting up cron schedule: $BACKUP_CRON"
  echo "$BACKUP_CRON /backup.sh >> /proc/1/fd/1 2>&1" | crontab -

  # Run initial backup if requested
  if [ "$BACKUP_ON_START" = "true" ]; then
    echo "Running initial backup..."
    /backup.sh || echo "Initial backup failed, continuing with cron..."
  fi

  echo "Starting crond..."
  exec crond -f -l 2
fi
