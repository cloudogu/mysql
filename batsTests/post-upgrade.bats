#! /bin/bash
export BATS_TEST_START_TIME="0"
export BATSLIB_FILE_PATH_REM=""
export BATSLIB_FILE_PATH_ADD=""

load '/workspace/target/bats_libs/bats-support/load.bash'
load '/workspace/target/bats_libs/bats-assert/load.bash'
load '/workspace/target/bats_libs/bats-file/load.bash'

setup() {
  export STARTUP_DIR=/workspace/resources
  WORKDIR="$(mktemp -d "${BATS_TMPDIR}/mysql-restore.XXXXXXXX")"
  export WORKDIR
  export MYSQL_VOLUME="${WORKDIR}/data"
  export DATABASE_CONFIG_DIR="${WORKDIR}/mysql-config"
  mkdir -p "${MYSQL_VOLUME}" "${WORKDIR}/var/ces/config" "${DATABASE_CONFIG_DIR}"
  touch "${DATABASE_CONFIG_DIR}/default-config.cnf" "${MYSQL_VOLUME}/original-data"

  mountpoint() { [[ -d "${2}" ]]; }
  doguctl() {
    case "$*" in
      'config local_state -d empty') cat "${WORKDIR}/state" ;;
      'config local_state upgrading') echo upgrading > "${WORKDIR}/state" ;;
      'config upgrade_dump_id -d none') cat "${WORKDIR}/dump-id" 2>/dev/null || echo none ;;
      'config upgrade_dump_id '*) echo "$3" > "${WORKDIR}/dump-id" ;;
      'config --rm upgrade_dump_id') rm -f "${WORKDIR}/dump-id" ;;
      'config --rm first_start_done') ;;
      'state upgrade done') [[ ! -f "${WORKDIR}/fail-status" ]] && touch "${WORKDIR}/done" ;;
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
  stage_dump 'CREATE TABLE test (id INT);'
}

teardown() {
  rm -rf -- "${WORKDIR:?}"
}

stage_dump() {
  DUMP_SQL="$1" bash -c '
    source "$STARTUP_DIR/pre-upgrade.sh"
    dumpData() { printf "%s" "$DUMP_SQL" > "$3"; }
    run_preupgrade 8.4.11-2 8.4.13-1
  '
  local id
  id="$(cat "${WORKDIR}/dump-id")"
  staged="${MYSQL_VOLUME}/.mysql-upgrade/${id}/alldb.sql"
  dump="${WORKDIR}/var/ces/config/mysql-upgrade/${id}/alldb.sql"
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
  rm "${staged}"
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_failure
  assert_file_exist "${MYSQL_VOLUME}/original-data"
  assert_file_not_exist "${WORKDIR}/done"

  stage_dump ''
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

@test "a previous attempt's dump or completion cannot supersede a new export for the same versions" {
  local failure previous_dir
  for failure in fail-import fail-status; do
    touch "${WORKDIR}/${failure}"
    run post_upgrade 8.4.11-2 8.4.13-1
    assert_failure
    rm "${WORKDIR}/${failure}"
    previous_dir="$(dirname "${dump}")"
    if [[ "${failure}" == fail-status ]]; then
      assert_file_exist "${previous_dir}/imported.sql"
    else
      assert_file_exist "${dump}"
    fi

    touch "${MYSQL_VOLUME}/original-data"
    stage_dump 'INSERT INTO test VALUES (42);'
    run post_upgrade 8.4.11-2 8.4.13-1
    assert_failure
    assert_file_exist "${MYSQL_VOLUME}/original-data"
    assert_equal "$(cat "${staged}")" 'INSERT INTO test VALUES (42);'
    assert_equal "$(cat "${WORKDIR}/state")" upgrading
    assert_file_not_exist "${WORKDIR}/done"

    # Simulate an operator archiving the unrelated recovery files before retrying.
    mv "${previous_dir}" "${WORKDIR}/${failure}-archive"
  done
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_success
  assert_equal "$(cat "${MYSQL_VOLUME}/imported")" 'INSERT INTO test VALUES (42);'
}
