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
  mysql_install_db="$(mock_create)"
  mysqld="$(mock_create)"
  mysql="$(mock_create)"

  export PATH="${PATH}:${BATS_TMPDIR}"
  ln -s "${doguctl}" "${BATS_TMPDIR}/doguctl"
  ln -s "${mysql_install_db}" "${BATS_TMPDIR}/mysql_install_db"
  ln -s "${mysqld}" "${BATS_TMPDIR}/mysqld"
  ln -s "${mysql}" "${BATS_TMPDIR}/mysql"
}

teardown() {
  unset STARTUP_DIR
  unset WORKDIR
  rm "${BATS_TMPDIR}/mysql_install_db"
  rm "${BATS_TMPDIR}/doguctl"
  rm "${BATS_TMPDIR}/mysqld"
  rm "${BATS_TMPDIR}/mysql"
}

@test "startup with existing db should only start mysql" {
  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"

  mock_set_status "${mysqld}" 0
  mock_set_status "${doguctl}" 0
  mock_set_output "${doguctl}" "NO" 3


  DATABASE_STORAGE="$(mktemp)"
  export DATABASE_STORAGE

  run runMain

  assert_success
  assert_equal "$(mock_get_call_args "${mysqld}" "1")" "--initialize-insecure"
  assert_equal "$(mock_get_call_args "${mysqld}" "2")" "--log-warnings=1"
  assert_equal "$(mock_get_call_num "${mysqld}")" "2"
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" "config container_config/memory_limit -d empty"
  assert_equal "$(mock_get_call_args "${doguctl}" "2")" "template /workspace/resources/default-config.cnf.tpl /workspace/resources/etc/my.cnf.dogu.d/default-config.cnf"
  assert_equal "$(mock_get_call_args "${doguctl}" "3")" "config first_start_done --default NO"
  assert_equal "$(mock_get_call_args "${doguctl}" "4")" "config first_start_done YES"
  assert_equal "$(mock_get_call_args "${doguctl}" "5")" "config --default ERROR logging/root"
  assert_equal "$(mock_get_call_args "${doguctl}" "6")" "state ready"
  assert_equal "$(mock_get_call_num "${doguctl}")" "6"
}

@test "applySecurityConfiguration" {
  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"

  mock_set_status "${doguctl}" 0
  mock_set_status "${mysql}" 0

  run applySecurityConfiguration

  assert_success
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" "wait --port 3306"
  assert_equal "$(mock_get_call_args "${mysql}" "1")" "-uroot -e DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  assert_equal "$(mock_get_call_args "${mysql}" "2")" "-uroot -e DROP DATABASE test;"
  assert_equal "$(mock_get_call_args "${mysql}" "3")" "-uroot -e DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  assert_equal "$(mock_get_call_args "${mysql}" "4")" "-uroot -e DELETE FROM mysql.user WHERE User='';"
  assert_equal "$(mock_get_call_args "${mysql}" "5")" "-uroot -e FLUSH PRIVILEGES;"

  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
  assert_equal "$(mock_get_call_num "${mysql}")" "5"
}

@test "calculateInnoDbBufferPoolSize() should return 512 MB (in bytes) if no RAM limit was set" {
  mock_set_status "${doguctl}" 0
  mock_set_output "${doguctl}" "empty" 1
  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"

  run calculateInnoDbBufferPoolSize

  assert_success
  assert_line "512M"
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" "config container_config/memory_limit -d empty"
  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
}

@test "calculateInnoDbBufferPoolSize() should return 512 MB (in bytes) if RAM limit was set but is less than 512 MB" {
  mock_set_status "${doguctl}" 0
  mock_set_output "${doguctl}" "100m" 1
  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"
  testMemoryFile="$(mktemp)"
  echo 100000000 > "${testMemoryFile}" # 100 MB
  export CONTAINER_MEMORY_LIMIT_FILE="${testMemoryFile}"

  run calculateInnoDbBufferPoolSize

  assert_success
  assert_line "512M"
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" "config container_config/memory_limit -d empty"
  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
}

@test "calculateInnoDbBufferPoolSize() should return 819 MB (in bytes, 80 %) if RAM limit was set to 1 GB" {
  mock_set_status "${doguctl}" 0
  mock_set_output "${doguctl}" "1g" 1

  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"
  testMemoryFile="$(mktemp)"
  echo 1073741824 > "${testMemoryFile}" # 1024 MB
  export CONTAINER_MEMORY_LIMIT_FILE="${testMemoryFile}"

  run calculateInnoDbBufferPoolSize

  assert_success
  assert_line "858993459"
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" "config container_config/memory_limit -d empty"
  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
}

@test "calculateInnoDbBufferPoolSize() should log error line when memory_limit was detected" {
  mock_set_status "${doguctl}" 0
  mock_set_output "${doguctl}" "1g" 1

  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"
  testMemoryFile="$(mktemp)"
  echo 7378697629510664192 > "${testMemoryFile}" # Something PB
  export CONTAINER_MEMORY_LIMIT_FILE="${testMemoryFile}"

  run calculateInnoDbBufferPoolSize

  assert_success # note: We do not fall back to a fixed value in order have the container crash so the admin needs to look at it
  assert_line "ERROR: Detected a memory limit of > 512 GB! Was 'memory_limit' set without re-creating the container?"
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" "config container_config/memory_limit -d empty"
  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
}
