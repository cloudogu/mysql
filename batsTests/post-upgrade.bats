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
  echo empty > "${WORKDIR}/state"

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
    # mysqld --initialize ignores dot-prefixed entries in the data directory.
    [[ -z "$(find "${MYSQL_VOLUME}" -mindepth 1 -maxdepth 1 ! -name '.*' -print -quit)" ]] || return 94
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
    mysql() { echo "${SOURCE_READ_ONLY:-1}"; }
    fenceSourceWrites() { :; }
    dumpData() {
      [[ ! -e "$WORKDIR/no-space-for-another-dump" ]] || return 28
      printf "%s" "$DUMP_SQL" > "$3"
    }
    run_preupgrade 8.4.11-2 "$1"
  ' _ "${2:-8.4.13-1}" || return $?
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
  # The same contents as the upgrade's option file do not make this operator file ours.
  printf '[mysqld]\nsuper_read_only=ON\n' > "${MYSQL_VOLUME}/.mysql-upgrade/source-read-only.cnf"
  cp "${MYSQL_VOLUME}/.mysql-upgrade/source-read-only.cnf" "${MYSQL_VOLUME}/.my.cnf"
  mkdir "${MYSQL_VOLUME}/.operator"
  echo keep > "${MYSQL_VOLUME}/.operator/note"

  run post_upgrade 8.4.11-2 8.4.13-1
  assert_failure
  assert_equal "$(cat "${dump}")" 'CREATE TABLE test (id INT);'
  assert_equal "$(cat "${WORKDIR}/state")" 'upgrading'
  assert_file_not_exist "${WORKDIR}/done"
  assert_file_exist "${MYSQL_VOLUME}/.my.cnf"

  rm "${WORKDIR}/fail-import"
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_success
  assert_equal "$(cat "${MYSQL_VOLUME}/imported")" 'CREATE TABLE test (id INT);'
  assert_file_exist "${MYSQL_VOLUME}/.my.cnf"
  assert_equal "$(cat "${MYSQL_VOLUME}/.operator/note")" keep
  assert_file_not_exist "${dump}"
  assert_file_exist "${WORKDIR}/done"

  touch "${MYSQL_VOLUME}/new-data"
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_success
  assert_file_exist "${MYSQL_VOLUME}/new-data"
}

@test "retrying the active fenced export needs no space for a second dump" {
  touch "${WORKDIR}/no-space-for-another-dump"
  run stage_dump 'unused'
  assert_success
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_success
  assert_equal "$(cat "${MYSQL_VOLUME}/imported")" 'CREATE TABLE test (id INT);'
}

@test "another target, a writable source, or an abandoned upgrade requires a fresh export" {
  stage_dump 'different target' 8.4.13-2
  assert_equal "$(cat "${staged}")" 'different target'
  SOURCE_READ_ONLY=0 stage_dump 'writes resumed' 8.4.13-2
  assert_equal "$(cat "${staged}")" 'writes resumed'
  echo empty > "${WORKDIR}/state"
  stage_dump 'new upgrade' 8.4.13-2
  assert_equal "$(cat "${staged}")" 'new upgrade'
}

@test "restore removes the 5.7 upgrade-owned option link" {
  local guard="${MYSQL_VOLUME}/.mysql-upgrade/source-read-only.cnf"
  printf '[mysqld]\nsuper_read_only=ON\n' > "${guard}"
  ln "${guard}" "${MYSQL_VOLUME}/.my.cnf"
  run post_upgrade 5.7.37-4 8.4.13-1
  assert_success
  assert_file_not_exist "${MYSQL_VOLUME}/.my.cnf"
  assert_dir_not_exist "${MYSQL_VOLUME}/.mysql-upgrade"
}

@test "failed cleanup sync leaves the restore identifiable after a crash" {
  sync() {
    local config_volume="${WORKDIR}/var/ces/config"
    if [[ "$*" == "-f ${config_volume}" && ! -d "${config_volume}/mysql-upgrade" ]]; then
      return 74
    fi
    command sync "$@"
  }
  export -f sync
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_equal "${status}" 74
  assert_file_exist "${WORKDIR}/dump-id"
  unset -f sync

  # Model the last synced directory entries reappearing on the config volume.
  mkdir -p "$(dirname "${dump}")/restoring"
  touch "$(dirname "${dump}")/imported.sql" "${MYSQL_VOLUME}/new-data"
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_success
  assert_file_exist "${MYSQL_VOLUME}/new-data"
  assert_file_not_exist "${WORKDIR}/dump-id"
  assert_dir_not_exist "${WORKDIR}/var/ces/config/mysql-upgrade"
}

@test "a failed copy can be retried without touching the original database" {
  cp() { printf 'incomplete' > "$2"; return 1; }
  export -f cp
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_failure
  assert_file_exist "${MYSQL_VOLUME}/original-data"
  assert_file_exist "${staged}"
  assert_file_not_exist "${WORKDIR}/done"

  unset -f cp
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_success
  assert_equal "$(cat "${MYSQL_VOLUME}/imported")" 'CREATE TABLE test (id INT);'
}

# Probe one startup iteration without a wall-clock timeout. A waiting startup exits at sleep.
probe_startup() {
  bash -c '
    source "$STARTUP_DIR/startup.sh"
    removeSocketIfExists() { :; }
    renderConfigFile() { :; }
    doguctl() { echo empty; [[ ! -f "$WORKDIR/read-error" ]]; }
    initializeMySql() { touch "$WORKDIR/startup-initialized"; }
    startMysql() { touch "$WORKDIR/started"; }
    sleep() { exit 75; }
    runMain
  '
}

@test "normal startup waits across the dump handoff and on an unreadable upgrade state" {
  # Startup sees an empty registry state even though the export is pending.
  run probe_startup
  assert_equal "${status}" 75
  assert_file_not_exist "${WORKDIR}/startup-initialized"

  # Run startup again while post-upgrade is importing, after the staging directory was wiped.
  export -f probe_startup
  mysql() {
    local status=0
    probe_startup >&2 || status=$?
    [[ "${status}" == 75 ]] || return 1
    cat > "${MYSQL_VOLUME}/imported"
  }
  export -f mysql
  run post_upgrade 8.4.11-2 8.4.13-1
  assert_success
  assert_file_not_exist "${WORKDIR}/startup-initialized"
  assert_file_not_exist "${WORKDIR}/started"

  touch "${WORKDIR}/read-error"
  run probe_startup
  assert_equal "${status}" 75
  assert_file_not_exist "${WORKDIR}/startup-initialized"
  rm "${WORKDIR}/read-error"
  run probe_startup
  assert_success
  assert_file_exist "${WORKDIR}/started"
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
