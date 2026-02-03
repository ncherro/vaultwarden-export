#!/bin/sh
# Shared functions for vaultwarden-export

# Helper function to get secret from env var or file
get_secret() {
  var_name="$1"
  file_var_name="${var_name}_FILE"

  # Check if file path is provided
  eval file_path="\$$file_var_name"
  if [ -n "$file_path" ] && [ -f "$file_path" ]; then
    tr -d '\n\r' < "$file_path"
    return
  fi

  # Fall back to direct env var
  eval value="\$$var_name"
  if [ -n "$value" ]; then
    printf '%s' "$value"
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
      # Read file, strip trailing whitespace
      value=$(tr -d '\n\r' < "$file_path")
      # Set and export the variable
      eval "$target_var=\$value"
      export "$target_var"
      echo "  Loaded $target_var from file"
    else
      echo "Warning: File not found for $var_name: $file_path" >&2
    fi
  done
}

# Extract prefix from filename pattern for retention matching
# e.g., "vaultwarden-%Y-%m-%d.json" -> "vaultwarden-"
get_backup_prefix() {
  filename_pattern="$1"
  printf '%s' "${filename_pattern%%%*}"
}
