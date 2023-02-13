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
  export WORKDIR=/workspace
  doguctl="$(mock_create)"
  export bundle
  export PATH="${PATH}:${BATS_TMPDIR}"
  ln -s "${doguctl}" "${BATS_TMPDIR}/doguctl"
}

teardown() {
  unset STARTUP_DIR
  unset WORKDIR
  rm "${BATS_TMPDIR}/doguctl"
}

@test "versions are the same - no script executed" {
  # shellcheck source=../resources/pre-upgrade.sh
  source "${STARTUP_DIR}/pre-upgrade.sh"

  run run_preupgrade "1.2.3-1" "1.2.3-1"

  assert_equal "$(mock_get_call_num "${doguctl}")" "0"
}

@test "5.7.37-1 - 8.0.32-1 => Dump starts" {
  # shellcheck source=../resources/pre-upgrade.sh
  source "${STARTUP_DIR}/pre-upgrade.sh"

  dumpData() {
      exit 123
  }

  run run_preupgrade "5.7.37-1" "8.0.32-1"
  echo $?

  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" 'state upgrading'
  assert_failure
  assert_equal "${status}" 123
}


@test "5.7.37-1 - 5.7.37-4 => Dump does not start" {
  # shellcheck source=../resources/pre-upgrade.sh
  source "${STARTUP_DIR}/pre-upgrade.sh"

  dumpData() {
      exit 123
  }

  run run_preupgrade "5.7.37-1" "5.7.37-4"
  echo $?

  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" 'state upgrading'
  assert_success
}

@test "8.0.32-1 - 8.0.32-4 => Dump does not start" {
  # shellcheck source=../resources/pre-upgrade.sh
  source "${STARTUP_DIR}/pre-upgrade.sh"

  dumpData() {
      exit 123
  }

  run run_preupgrade "8.0.32-1" "8.0.32-4"
  echo $?

  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" 'state upgrading'
  assert_success
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
