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

  run run_postupgrade "1.2.3-1" "1.2.3-1"

  assert_equal "$(mock_get_call_num "${doguctl}")" "0"
}

@test "/alldb.sql exists => Import starts" {
  # shellcheck source=../resources/pre-upgrade.sh
  source "${STARTUP_DIR}/post-upgrade.sh"

  restoreDump() {
      exit 123
  }

  mkdir -p "${WORKDIR}/var/lib/mysql"
  touch "${WORKDIR}/var/lib/mysql/alldb.sql"

  run run_postupgrade "5.7.37-1" "8.0.32-1"

  assert_equal "$(mock_get_call_num "${doguctl}")" "0"
  assert_failure
  assert_equal "${status}" 123
}

@test "/alldb.sql does not exist => Import starts" {
  # shellcheck source=../resources/pre-upgrade.sh
  source "${STARTUP_DIR}/post-upgrade.sh"

  restoreDump() {
      exit 123
  }

  rm -f "${WORKDIR}/var/lib/mysql/alldb.sql"

  run run_postupgrade "5.7.37-1" "8.0.32-1"

  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" 'state upgrade done'
  assert_success
}
