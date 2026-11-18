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

# Convert a strftime filename pattern into an anchored extended regex that
# matches only filenames this pattern could have produced.
# e.g., "vaultwarden-%Y-%m-%d.json" -> "^vaultwarden-[0-9]{4}-[0-9]{2}-[0-9]{2}\.json$"
# Returns 1 (and prints nothing) if the pattern uses an unsupported specifier,
# so callers can skip retention instead of guessing.
pattern_to_regex() {
  rest="$1"
  regex=""
  while [ -n "$rest" ]; do
    char="${rest%"${rest#?}"}"
    rest="${rest#?}"
    if [ "$char" = "%" ]; then
      spec="${rest%"${rest#?}"}"
      rest="${rest#?}"
      case "$spec" in
        Y|G) regex="${regex}[0-9]{4}" ;;
        y|g|m|d|H|I|M|S|U|V|W) regex="${regex}[0-9]{2}" ;;
        j) regex="${regex}[0-9]{3}" ;;
        u|w) regex="${regex}[0-9]" ;;
        s) regex="${regex}[0-9]+" ;;
        F) regex="${regex}[0-9]{4}-[0-9]{2}-[0-9]{2}" ;;
        T) regex="${regex}[0-9]{2}:[0-9]{2}:[0-9]{2}" ;;
        a|A|b|B|h|p) regex="${regex}[A-Za-z]+" ;;
        %) regex="${regex}%" ;;
        *) return 1 ;;
      esac
    else
      case "$char" in
        '.'|'['|']'|'('|')'|'*'|'+'|'?'|'{'|'}'|'|'|'^'|'$'|"\\")
          regex="${regex}\\${char}" ;;
        *) regex="${regex}${char}" ;;
      esac
    fi
  done
  printf '^%s$' "$regex"
}

# Select backups to delete under the retention policy.
# Reads "modtime;filename" lines (rclone lsf --format tp) on stdin and prints
# the filenames to delete: those matching the filename pattern, newest first by
# modification time (then name), beyond the newest $keep. $current (the file
# just uploaded) is never printed.
select_backups_to_delete() {
  filename_pattern="$1"
  keep="$2"
  current="$3"

  regex=$(pattern_to_regex "$filename_pattern") || return 1

  while IFS= read -r line; do
    name="${line#*;}"
    if printf '%s\n' "$name" | grep -Eq -- "$regex"; then
      printf '%s\n' "$line"
    fi
  done | \
    sort -t ';' -k1,1r -k2r | \
    tail -n +$((keep + 1)) | \
    while IFS= read -r line; do
      name="${line#*;}"
      [ "$name" = "$current" ] && continue
      printf '%s\n' "$name"
    done
}
