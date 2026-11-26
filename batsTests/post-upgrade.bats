#! /bin/bash
export BATS_TEST_START_TIME="0"
export BATSLIB_FILE_PATH_REM=""
export BATSLIB_FILE_PATH_ADD=""

load '/workspace/target/bats_libs/bats-support/load.bash'
load '/workspace/target/bats_libs/bats-assert/load.bash'
load '/workspace/target/bats_libs/bats-file/load.bash'

setup() {
  export STARTUP_DIR=/workspace/resources
  export WORKDIR="${BATS_TEST_TMPDIR}"
  export MYSQL_VOLUME="${WORKDIR}/data"
  export DATABASE_CONFIG_DIR="${WORKDIR}/mysql-config"
  export staged="${MYSQL_VOLUME}/.mysql-upgrade/alldb.sql"
  export dump="${WORKDIR}/var/ces/config/mysql-upgrade/alldb.sql"
  mkdir -p "$(dirname "${staged}")" "${WORKDIR}/var/ces/config" "${DATABASE_CONFIG_DIR}"
  touch "${DATABASE_CONFIG_DIR}/default-config.cnf" "${MYSQL_VOLUME}/original-data"
  printf 'upgrading\n' > "${WORKDIR}/state"

  mountpoint() { [[ -d "${2}" ]]; }
  doguctl() {
    case "$*" in
      'config local_state -d empty') cat "${WORKDIR}/state" ;;
      'config --rm first_start_done') ;;
      'state upgrade done') touch "${WORKDIR}/done" ;;
      'config --rm local_state') printf 'empty\n' > "${WORKDIR}/state" ;;
      *) return 1 ;;
    esac
  }
  initializeMySql() {
    [[ -z "$(ls -A "${MYSQL_VOLUME}")" ]] || return 94
    touch "${MYSQL_VOLUME}/initialized"
  }
  startMysqlInBackground() { true & }
  mysql() {
    cat > "${MYSQL_VOLUME}/imported"
    [[ ! -e "${WORKDIR}/fail-import" ]]
  }
  mysqladmin() { true; }
  export -f mountpoint doguctl initializeMySql startMysqlInBackground mysql mysqladmin
}

post_upgrade() {
  bash -c 'source "$STARTUP_DIR/post-upgrade.sh"; run_postupgrade "$@"' _ "$@"
}

@test "identical versions leave the data untouched" {
  run post_upgrade 1.2.3-1 1.2.3-1
  assert_success
  assert_file_exist "${MYSQL_VOLUME}/original-data"
  assert_file_not_exist "${WORKDIR}/done"
}

@test "failed import retains the dump, retry starts clean, and successful replay does not wipe data" {
  printf 'CREATE TABLE test (id INT);\n' > "${staged}"
  touch "${WORKDIR}/fail-import"

  run post_upgrade 8.4.11-2 8.4.13-1
  assert_failure
  assert_equal "$(cat "${dump}")" 'CREATE TABLE test (id INT);'
  assert_equal "$(cat "${WORKDIR}/state")" 'upgrading'
  assert_file_not_exist "${WORKDIR}/done"

  rm "${WORKDIR}/fail-import"
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_success
  assert_equal "$(cat "${MYSQL_VOLUME}/imported")" 'CREATE TABLE test (id INT);'
  assert_file_not_exist "${dump}"
  assert_file_exist "${WORKDIR}/done"

  touch "${MYSQL_VOLUME}/new-data"
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_success
  assert_file_exist "${MYSQL_VOLUME}/new-data"
}

@test "missing dump blocks upgrade but an intentional empty dump does not" {
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_failure
  assert_file_exist "${MYSQL_VOLUME}/original-data"
  assert_file_not_exist "${WORKDIR}/done"

  touch "${staged}"
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_success
  assert_file_exist "${WORKDIR}/done"
  assert_file_not_exist "${MYSQL_VOLUME}/imported"
}

@test "interrupted restore retains the dump and does not wipe the data again" {
  mkdir -p "$(dirname "${dump}")/restoring"
  printf 'CREATE TABLE test (id INT);\n' > "${dump}"

  run post_upgrade 8.4.11-2 8.4.13-1
  assert_failure
  assert_file_exist "${dump}"
  assert_file_exist "${MYSQL_VOLUME}/original-data"
  assert_equal "$(cat "${WORKDIR}/state")" 'upgrading'
  assert_file_not_exist "${WORKDIR}/done"
}
