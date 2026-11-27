#! /bin/bash
# Bind an unbound BATS variables that fail all tests when combined with 'set -o nounset'
export BATS_TEST_START_TIME="0"
export BATSLIB_FILE_PATH_REM=""
export BATSLIB_FILE_PATH_ADD=""

load '/workspace/target/bats_libs/bats-support/load.bash'
load '/workspace/target/bats_libs/bats-assert/load.bash'
load '/workspace/target/bats_libs/bats-mock/load.bash'
load '/workspace/target/bats_libs/bats-file/load.bash'


setup() {
  export STARTUP_DIR=/workspace/resources
  MYSQL_VOLUME="$(mktemp -d "${BATS_TMPDIR}/mysql-data.XXXXXXXX")"
  export MYSQL_VOLUME
  mountpoint() { [[ "${2}" == "${MYSQL_VOLUME}" ]]; }
  doguctl="$(mock_create)"
  export bundle
  export PATH="${MYSQL_VOLUME}:${PATH}"
  ln -s "${doguctl}" "${MYSQL_VOLUME}/doguctl"
}

teardown() {
  rm -rf -- "${MYSQL_VOLUME:?}"
}

@test "versions are the same - no script executed" {
  # shellcheck source=../resources/pre-upgrade.sh
  source "${STARTUP_DIR}/pre-upgrade.sh"

  run run_preupgrade "1.2.3-1" "1.2.3-1"

  assert_equal "$(mock_get_call_num "${doguctl}")" "0"
}

@test "failed exports reclaim partials on retry without deleting a completed dump" {
  # shellcheck source=../resources/pre-upgrade.sh
  source "${STARTUP_DIR}/pre-upgrade.sh"

  local staging="${MYSQL_VOLUME}/.mysql-upgrade"
  mkdir -p "${staging}/oldcompleted" "${staging}/oldabandoned"
  echo 'completed export' > "${staging}/oldcompleted/alldb.sql"
  echo 'interrupted export' > "${staging}/oldabandoned/alldb.partial"
  dumpData() {
      echo 'partial export' > "$3"
      exit 123
  }

  for _ in 1 2; do
    run run_preupgrade "5.7.37-1" "8.0.32-1"
    assert_equal "${status}" 123
    assert_equal "$(find "${staging}" -type f -name 'alldb.*')" "${staging}/oldcompleted/alldb.sql"
    assert_equal "$(cat "${staging}/oldcompleted/alldb.sql")" 'completed export'
  done
}

@test "versionXLessOrEqualThanY() should return true for versions less than or equal to another" {
  source /workspace/resources/pre-upgrade.sh

  run versionXLessOrEqualThanY "1.0.0-1" "1.0.0-1"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "1.0.0-2"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "1.1.0-2"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "1.0.2-2"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "1.0.0-2"
  assert_success
  run versionXLessOrEqualThanY "1.1.0-1" "1.1.0-2"
  assert_success
  run versionXLessOrEqualThanY "1.0.2-1" "1.0.2-2"
  assert_success
  run versionXLessOrEqualThanY "1.2.3-4" "1.2.3-4"
  assert_success
  run versionXLessOrEqualThanY "1.2.3-4" "1.2.3-5"
  assert_success

  run versionXLessOrEqualThanY "1.0.0-1" "2.0.0-1"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "2.1.0-1"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "2.0.1-1"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "2.1.1-1"
  assert_success
}

@test "versionXLessOrEqualThanY() should return false for versions greater than another" {
  source /workspace/resources/pre-upgrade.sh

  run versionXLessOrEqualThanY "0.0.0-10" "0.0.0-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-1" "0.0.0-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-1" "0.0.9-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-1" "0.9.9-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-0" "0.9.9-9"
  assert_failure
  run versionXLessOrEqualThanY "1.1.0-1" "0.0.0-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-1" "0.0.9-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-1" "0.9.9-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-0" "0.9.9-9"
  assert_failure

  run versionXLessOrEqualThanY "1.2.3-4" "0.1.2-3"
  assert_failure
  run versionXLessOrEqualThanY "1.2.3-5" "0.1.2-3"
  assert_failure

  run versionXLessOrEqualThanY "2.0.0-1" "1.0.0-1"
  assert_failure
  run versionXLessOrEqualThanY "2.1.0-1" "1.0.0-1"
  assert_failure
  run versionXLessOrEqualThanY "2.0.1-1" "1.0.0-1"
  assert_failure
  run versionXLessOrEqualThanY "2.1.1-1" "1.0.0-1"
  assert_failure
}

@test "versionXLessThanY() should return true for versions less than another" {
  source /workspace/resources/pre-upgrade.sh

  run versionXLessThanY "1.0.0-1" "1.0.0-2"
  assert_success
  run versionXLessThanY "1.0.0-1" "1.1.0-2"
  assert_success
  run versionXLessThanY "1.0.0-1" "1.0.2-2"
  assert_success
  run versionXLessThanY "1.0.0-1" "1.0.0-2"
  assert_success
  run versionXLessThanY "1.1.0-1" "1.1.0-2"
  assert_success
  run versionXLessThanY "1.0.2-1" "1.0.2-2"
  assert_success
  run versionXLessThanY "1.2.3-4" "1.2.3-5"
  assert_success

  run versionXLessThanY "1.0.0-1" "2.0.0-1"
  assert_success
  run versionXLessThanY "1.0.0-1" "2.1.0-1"
  assert_success
  run versionXLessThanY "1.0.0-1" "2.0.1-1"
  assert_success
  run versionXLessThanY "1.0.0-1" "2.1.1-1"
  assert_success
}

@test "versionXLessThanY() should return false for versions greater than another" {
  source /workspace/resources/pre-upgrade.sh

  run versionXLessThanY "1.0.0-1" "1.0.0-1"
  assert_failure
  run versionXLessThanY "0.0.0-10" "0.0.0-9"
  assert_failure
  run versionXLessThanY "1.0.0-1" "0.0.0-9"
  assert_failure
  run versionXLessThanY "1.0.0-1" "0.0.9-9"
  assert_failure
  run versionXLessThanY "1.0.0-1" "0.9.9-9"
  assert_failure
  run versionXLessThanY "1.0.0-0" "0.9.9-9"
  assert_failure
  run versionXLessThanY "1.1.0-1" "0.0.0-9"
  assert_failure
  run versionXLessThanY "1.0.0-1" "0.0.9-9"
  assert_failure
  run versionXLessThanY "1.0.0-1" "0.9.9-9"
  assert_failure
  run versionXLessThanY "1.0.0-0" "0.9.9-9"

  run versionXLessThanY "1.2.3-4" "0.1.2-3"
  assert_failure
  run versionXLessThanY "1.2.3-5" "0.1.2-3"
  assert_failure

  run versionXLessThanY "2.0.0-1" "1.0.0-1"
  assert_failure
  run versionXLessThanY "2.1.0-1" "1.0.0-1"
  assert_failure
  run versionXLessThanY "2.0.1-1" "1.0.0-1"
  assert_failure
  run versionXLessThanY "2.1.1-1" "1.0.0-1"
  assert_failure
}
