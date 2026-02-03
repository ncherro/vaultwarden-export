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

# get_backup_prefix tests

@test "get_backup_prefix extracts prefix from default pattern" {
  result=$(get_backup_prefix "vaultwarden-%Y-%m-%d.json")
  [ "$result" = "vaultwarden-" ]
}

@test "get_backup_prefix extracts prefix from custom pattern" {
  result=$(get_backup_prefix "backup-%Y%m%d.json")
  [ "$result" = "backup-" ]
}

@test "get_backup_prefix handles pattern with no prefix" {
  result=$(get_backup_prefix "%Y-%m-%d.json")
  [ "$result" = "" ]
}

@test "get_backup_prefix handles pattern with long prefix" {
  result=$(get_backup_prefix "my-vaultwarden-backup-%Y-%m-%d.json")
  [ "$result" = "my-vaultwarden-backup-" ]
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
