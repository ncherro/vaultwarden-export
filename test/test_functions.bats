#!/usr/bin/env bats

setup() {
  # Load the functions
  . "$BATS_TEST_DIRNAME/../lib/functions.sh"

  # Create temp directory for test files
  TEST_TEMP_DIR="$(mktemp -d)"
}

teardown() {
  # Clean up temp directory
  rm -rf "$TEST_TEMP_DIR"
}

# get_secret tests

@test "get_secret returns value from environment variable" {
  export TEST_VAR="secret_value"
  result=$(get_secret TEST_VAR)
  [ "$result" = "secret_value" ]
}

@test "get_secret returns value from file when _FILE is set" {
  echo -n "file_secret" > "$TEST_TEMP_DIR/secret.txt"
  export TEST_VAR_FILE="$TEST_TEMP_DIR/secret.txt"
  result=$(get_secret TEST_VAR)
  [ "$result" = "file_secret" ]
}

@test "get_secret prefers file over environment variable" {
  export TEST_VAR="env_value"
  echo -n "file_value" > "$TEST_TEMP_DIR/secret.txt"
  export TEST_VAR_FILE="$TEST_TEMP_DIR/secret.txt"
  result=$(get_secret TEST_VAR)
  [ "$result" = "file_value" ]
}

@test "get_secret strips newlines from file" {
  printf "secret_with_newline\n" > "$TEST_TEMP_DIR/secret.txt"
  export TEST_VAR_FILE="$TEST_TEMP_DIR/secret.txt"
  result=$(get_secret TEST_VAR)
  [ "$result" = "secret_with_newline" ]
}

@test "get_secret strips carriage returns from file" {
  printf "secret_with_cr\r\n" > "$TEST_TEMP_DIR/secret.txt"
  export TEST_VAR_FILE="$TEST_TEMP_DIR/secret.txt"
  result=$(get_secret TEST_VAR)
  [ "$result" = "secret_with_cr" ]
}

@test "get_secret fails when neither var nor file is set" {
  unset MISSING_VAR
  unset MISSING_VAR_FILE
  run get_secret MISSING_VAR
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error"* ]]
}

@test "get_secret fails when file does not exist" {
  export TEST_VAR_FILE="/nonexistent/path"
  unset TEST_VAR
  run get_secret TEST_VAR
  [ "$status" -eq 1 ]
}

# pattern_to_regex tests

@test "pattern_to_regex converts default pattern" {
  result=$(pattern_to_regex "vaultwarden-%Y-%m-%d.json")
  [ "$result" = '^vaultwarden-[0-9]{4}-[0-9]{2}-[0-9]{2}\.json$' ]
}

@test "pattern_to_regex anchors date-only pattern so unrelated files don't match" {
  regex=$(pattern_to_regex "%Y-%m-%d.json")
  echo "2026-11-17.json" | grep -Eq "$regex"
  ! echo "notes.txt" | grep -Eq "$regex"
  ! echo "zzz-2026-11-17.json" | grep -Eq "$regex"
  ! echo "2026-11-17.json.bak" | grep -Eq "$regex"
}

@test "pattern_to_regex doesn't match another vault's default filename" {
  regex=$(pattern_to_regex "vaultwarden-%Y-%m-%d.json")
  ! echo "vaultwarden-org-abc-2026-11-17.json" | grep -Eq "$regex"
}

@test "pattern_to_regex escapes regex metacharacters" {
  regex=$(pattern_to_regex "a.b+(c)-%Y.json")
  echo "a.b+(c)-2026.json" | grep -Eq "$regex"
  ! echo "aXbb(c)-2026.json" | grep -Eq "$regex"
}

@test "pattern_to_regex handles time specifiers and literal percent" {
  regex=$(pattern_to_regex "bk-%FT%T-%s-100%%.json")
  echo "bk-2026-11-17T04:00:00-1763352000-100%.json" | grep -Eq "$regex"
}

@test "pattern_to_regex fails on unsupported specifier" {
  run pattern_to_regex "backup-%Q.json"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# select_backups_to_delete tests

@test "select_backups_to_delete keeps newest N matching files" {
  result=$(printf '%s\n' \
    "2026-11-14 04:00:00;vaultwarden-2026-11-14.json" \
    "2026-11-15 04:00:00;vaultwarden-2026-11-15.json" \
    "2026-11-16 04:00:00;vaultwarden-2026-11-16.json" \
    "2026-11-17 04:00:00;vaultwarden-2026-11-17.json" \
    | select_backups_to_delete "vaultwarden-%Y-%m-%d.json" 2 "vaultwarden-2026-11-17.json")
  [ "$result" = "$(printf '%s\n' vaultwarden-2026-11-15.json vaultwarden-2026-11-14.json)" ]
}

@test "select_backups_to_delete ignores unrelated files with date-only pattern" {
  result=$(printf '%s\n' \
    "2026-11-20 00:00:00;zzz-notes.txt" \
    "2026-11-20 00:00:00;readme.md" \
    "2026-11-16 04:00:00;2026-11-16.json" \
    "2026-11-17 04:00:00;2026-11-17.json" \
    | select_backups_to_delete "%Y-%m-%d.json" 1 "2026-11-17.json")
  [ "$result" = "2026-11-16.json" ]
}

@test "select_backups_to_delete leaves other vaults' backups alone" {
  result=$(printf '%s\n' \
    "2026-11-15 04:00:00;vaultwarden-org-abc-2026-11-15.json" \
    "2026-11-16 04:00:00;vaultwarden-org-abc-2026-11-16.json" \
    "2026-11-16 04:00:00;vaultwarden-2026-11-16.json" \
    "2026-11-17 04:00:00;vaultwarden-2026-11-17.json" \
    | select_backups_to_delete "vaultwarden-%Y-%m-%d.json" 1 "vaultwarden-2026-11-17.json")
  [ "$result" = "vaultwarden-2026-11-16.json" ]
}

@test "select_backups_to_delete orders by modtime, not name" {
  result=$(printf '%s\n' \
    "2026-10-31 04:00:00;backup-31-10-2026.json" \
    "2026-11-01 04:00:00;backup-01-11-2026.json" \
    | select_backups_to_delete "backup-%d-%m-%Y.json" 1 "backup-01-11-2026.json")
  [ "$result" = "backup-31-10-2026.json" ]
}

@test "select_backups_to_delete never deletes the file just uploaded" {
  # Current file has an older modtime than a stray future-dated match
  result=$(printf '%s\n' \
    "2030-01-01 00:00:00;vaultwarden-2030-01-01.json" \
    "2026-11-17 04:00:00;vaultwarden-2026-11-17.json" \
    | select_backups_to_delete "vaultwarden-%Y-%m-%d.json" 1 "vaultwarden-2026-11-17.json")
  [ -z "$result" ]
}

@test "select_backups_to_delete fails on unsupported pattern" {
  run sh -c '. "$1"; echo "x;y" | select_backups_to_delete "b-%Q" 1 y' _ "$BATS_TEST_DIRNAME/../lib/functions.sh"
  [ "$status" -eq 1 ]
}

# load_rclone_secrets tests

@test "load_rclone_secrets loads secrets from files" {
  echo -n "my_access_key" > "$TEST_TEMP_DIR/access_key.txt"
  export RCLONE_CONFIG_S3_ACCESS_KEY_ID_FILE="$TEST_TEMP_DIR/access_key.txt"

  load_rclone_secrets

  [ "$RCLONE_CONFIG_S3_ACCESS_KEY_ID" = "my_access_key" ]
}

@test "load_rclone_secrets warns on missing file" {
  export RCLONE_CONFIG_S3_SECRET_FILE="/nonexistent/file"

  run load_rclone_secrets

  [[ "$output" == *"Warning"* ]]
}
