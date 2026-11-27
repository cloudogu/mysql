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
  export MYSQL_VOLUME=/workspace/var/lib/mysql
  # never read the cgroup of the test container; tests write the limit files they need
  CGROUP_TEST_DIR="$(mktemp -d)"
  export CGROUP_V2_MEMORY_LIMIT_FILE="${CGROUP_TEST_DIR}/memory.max"
  export CGROUP_V1_MEMORY_LIMIT_FILE="${CGROUP_TEST_DIR}/memory.limit_in_bytes"
  doguctl="$(mock_create)"
  mysql_install_db="$(mock_create)"
  mysqld="$(mock_create)"
  mysql="$(mock_create)"
  runuser="$(mock_create)"

  export PATH="${PATH}:${BATS_TMPDIR}"
  ln -s "${doguctl}" "${BATS_TMPDIR}/doguctl"
  ln -s "${mysql_install_db}" "${BATS_TMPDIR}/mysql_install_db"
  ln -s "${mysqld}" "${BATS_TMPDIR}/mysqld"
  ln -s "${mysql}" "${BATS_TMPDIR}/mysql"
  ln -s "${runuser}" "${BATS_TMPDIR}/runuser"
}

teardown() {
  unset STARTUP_DIR
  unset WORKDIR
  rm -rf "${CGROUP_TEST_DIR}"
  rm "${BATS_TMPDIR}/mysql_install_db"
  rm "${BATS_TMPDIR}/doguctl"
  rm "${BATS_TMPDIR}/mysqld"
  rm "${BATS_TMPDIR}/mysql"
  rm "${BATS_TMPDIR}/runuser"
}

@test "startup with existing db should only start mysql" {
  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"

  mock_set_status "${mysqld}" 0
  mock_set_status "${doguctl}" 0
  mock_set_output "${doguctl}" "NO" 3
  mock_set_status "${runuser}" 0


  DATABASE_STORAGE="$(mktemp)"
  export DATABASE_STORAGE

  run runMain

  assert_success
  assert_equal "$(mock_get_call_args "${mysqld}" "1")" "--initialize-insecure"
  assert_equal "$(mock_get_call_num "${mysqld}")" "1"
  assert_equal "$(mock_get_call_args "${runuser}" "1")" "-u mysql -- mysqld --datadir=/workspace/var/lib/mysql --log_error_verbosity=2"
  assert_equal "$(mock_get_call_num "${runuser}")" "1"
  assert_equal "$(mock_get_call_args "${doguctl}" "1")" "template /workspace/resources/default-config.cnf.tpl /workspace/resources/etc/my.cnf.dogu.d/default-config.cnf"
  assert_equal "$(mock_get_call_args "${doguctl}" "2")" "config local_state -d empty"
  assert_equal "$(mock_get_call_args "${doguctl}" "3")" "config first_start_done --default NO"
  assert_equal "$(mock_get_call_args "${doguctl}" "4")" "config first_start_done YES"
  assert_equal "$(mock_get_call_args "${doguctl}" "5")" "config --default WARN logging/root"
  assert_equal "$(mock_get_call_args "${doguctl}" "6")" "state ready"
  assert_equal "$(mock_get_call_args "${doguctl}" "7")" "config local_state -d empty"
  assert_equal "$(mock_get_call_args "${doguctl}" "8")" "config --rm local_state"
  assert_equal "$(mock_get_call_num "${doguctl}")" "8"
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

@test "removeSocketIfExists should remove socket file" {
  mkdir -p "${STARTUP_DIR}/var/run/mysqld"
  touch "${STARTUP_DIR}/var/run/mysqld/mysqld.sock.lock"
  touch "${STARTUP_DIR}/var/run/mysqld/mysqld.sock"

  assert_file_exist "${STARTUP_DIR}/var/run/mysqld/mysqld.sock.lock"
  assert_file_exist "${STARTUP_DIR}/var/run/mysqld/mysqld.sock"

  source "${STARTUP_DIR}/startup.sh"

  run removeSocketIfExists

  assert_success
  assert_output --partial 'Removing mysql lockfile if existing...'
  assert_file_not_exist "${STARTUP_DIR}/var/run/mysqld/mysqld.sock.lock"
  assert_file_not_exist "${STARTUP_DIR}/var/run/mysqld/mysqld.sock"
  rm -rf "${STARTUP_DIR}/var/lib/mysql"
  rm -rf "${STARTUP_DIR}/var/run/mysql"
}

@test "removeSocketIfExists should not fail when file not exists" {
  mkdir -p "${STARTUP_DIR}/var/run/mysqld"

  assert_file_not_exist "${STARTUP_DIR}/var/run/mysqld/mysqld.sock.lock"
  assert_file_not_exist "${STARTUP_DIR}/var/run/mysqld/mysqld.sock"

  source "${STARTUP_DIR}/startup.sh"

  run removeSocketIfExists

  assert_success
  assert_output --partial 'Removing mysql lockfile if existing...'
  assert_file_not_exist "${STARTUP_DIR}/var/run/mysqld/mysqld.sock.lock"
  assert_file_not_exist "${STARTUP_DIR}/var/run/mysqld/mysqld.sock"

  # Necessary cleanup to prevent having root-permission directories/files in the project folder after test execution.
  # Using rmdir to make this test fail in case resources/var should actually contain files later.
  rmdir "${STARTUP_DIR}/var/run/mysqld"
  rmdir "${STARTUP_DIR}/var/run"
  rmdir "${STARTUP_DIR}/var"
}

@test "regression #68: limit of 800 MiB is detected without CONTAINER_MEMORY_LIMIT_FILE" {
  # Situation from https://github.com/cloudogu/mysql/issues/68: the container has a cgroup v2 limit of 800 MiB, CONTAINER_MEMORY_LIMIT_FILE is not set.
  # Before the fix: "CONTAINER_MEMORY_LIMIT_FILE: unbound variable" and a fixed fallback to 512M.
  unset CONTAINER_MEMORY_LIMIT_FILE
  echo 838860800 > "${CGROUP_V2_MEMORY_LIMIT_FILE}" # 800 MiB
  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"

  run calculateInnoDbBufferPoolSize

  assert_success
  refute_output --partial "unbound variable"
  refute_output --partial "ERROR"
  refute_output "512M"
  assert_output "268435456" # 256 MiB: largest power of two <= 400 MiB
}

@test "calculateInnoDbBufferPoolSize() should return 512M if the container has no memory limit" {
  echo "max" > "${CGROUP_V2_MEMORY_LIMIT_FILE}"
  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"

  run calculateInnoDbBufferPoolSize

  assert_success
  assert_output "512M"
}

@test "calculateInnoDbBufferPoolSize() should return 512M if cgroup v1 reports no memory limit" {
  echo 9223372036854771712 > "${CGROUP_V1_MEMORY_LIMIT_FILE}"
  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"

  run calculateInnoDbBufferPoolSize

  assert_success
  assert_output "512M"
}

@test "calculateInnoDbBufferPoolSize() should read the limit from cgroup v1 if cgroup v2 is not available" {
  echo 1073741824 > "${CGROUP_V1_MEMORY_LIMIT_FILE}" # 1 GiB
  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"

  run calculateInnoDbBufferPoolSize

  assert_success
  assert_output "536870912" # 512 MiB: exactly half
}

@test "calculateInnoDbBufferPoolSize() should use the largest power of two that is at most half of the limit" {
  # shellcheck source=/workspace/resources/startup.sh
  source "${STARTUP_DIR}/startup.sh"
  local mib=1048576
  # limit in MiB -> expected buffer pool in MiB
  local cases=("300 128" "512 256" "600 256" "1023 256" "2047 512" "2048 1024" "4096 2048" "8192 4096")

  for c in "${cases[@]}"; do
    read -r limit expected <<<"${c}"
    echo $((limit * mib)) > "${CGROUP_V2_MEMORY_LIMIT_FILE}"
    run calculateInnoDbBufferPoolSize
    assert_success
    assert_output "$((expected * mib))"
  done
}
