#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

function run_postupgrade() {
  local FROM_VERSION="${1}"
  local TO_VERSION="${2}"

  if [ "${FROM_VERSION}" = "${TO_VERSION}" ]; then
    echo "FROM and TO versions are the same; Exiting..."
    exit 0
  fi

  local config_volume="${WORKDIR:-}/var/ces/config"
  local dump_dir="${config_volume}/mysql-upgrade"
  local dump_file="${dump_dir}/alldb.sql"
  local staged_dump="${MYSQL_VOLUME}/.mysql-upgrade/alldb.sql"

  if ! mountpoint -q "${config_volume}"; then
    echo "ERROR: Upgrade dump volume ${config_volume} is not mounted" >&2
    return 1
  fi
  if ! mountpoint -q "${MYSQL_VOLUME}"; then
    echo "ERROR: MySQL data volume ${MYSQL_VOLUME} is not mounted" >&2
    return 1
  fi
  local state
  state="$(doguctl config local_state -d empty)"

  if [[ -f "${dump_dir}/imported.sql" ]]; then
    # The import has finished; only the final status or cleanup may be pending.
    if [[ -d "${dump_dir}/restoring" ]]; then
      rmdir "${dump_dir}/restoring"
    fi
  elif [[ "${state}" != "upgrading" ]]; then
    if [[ -f "${dump_file}" || -f "${staged_dump}" ]]; then
      echo "ERROR: Pending upgrade dump without upgrade state; refusing to restore" >&2
      return 1
    fi
    return 0
  else
    install -d -m 700 "${dump_dir}"
    if ! mkdir "${dump_dir}/restoring"; then
      echo "ERROR: Previous restore did not stop cleanly; inspect ${dump_dir} before retrying" >&2
      return 1
    fi
    if [[ ! -f "${dump_file}" ]]; then
      if [[ ! -f "${staged_dump}" ]]; then
        rmdir "${dump_dir}/restoring"
        echo "ERROR: Expected upgrade dump is missing; refusing to initialize MySQL" >&2
        return 1
      fi
      cp "${staged_dump}" "${dump_dir}/alldb.partial"
      mv "${dump_dir}/alldb.partial" "${dump_file}"
    fi
    sync -f "${dump_dir}"

    # MySQL needs an empty data directory, including when retrying a failed import.
    find "${MYSQL_VOLUME}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    doguctl config --rm first_start_done

    if [[ -s "${dump_file}" ]]; then
      restoreDump "${dump_file}" "${dump_dir}/restoring"
    fi
    sync -f "${MYSQL_VOLUME}"
    mv "${dump_file}" "${dump_dir}/imported.sql"
    sync -f "${dump_dir}"
    rmdir "${dump_dir}/restoring"
  fi

  echo "Set registry flag so startup script can start afterwards..."
  if [[ "${state}" == "upgrading" ]]; then
    doguctl state "upgrade done"
    doguctl config --rm "local_state"
  fi
  rm "${dump_dir}/imported.sql"

  echo "Mysql post-upgrade done"
}

restoreDump() {
  local dump_file="${1}"
  local restoring="${2}"
  while [[ ! -f "${DATABASE_CONFIG_DIR}/default-config.cnf" ]]; do
    echo "Wait for preparations"
    sleep 3
  done

  initializeMySql
  local socket="${STARTUP_DIR}/var/run/mysqld/upgrade.sock"
  startMysqlInBackground "${socket}"
  local mysql_pid=$!

  echo "Reimport data from last version..."
  local import_status=0
  mysql --protocol=socket --socket="${socket}" -u root <"${dump_file}" || import_status=$?

  echo "Shutdown mysql"
  mysqladmin --protocol=socket --socket="${socket}" shutdown
  wait "${mysql_pid}"
  if (( import_status != 0 )); then
    rmdir "${restoring}"
    echo "ERROR: MySQL import failed; the dump was retained at ${dump_file}" >&2
    return "${import_status}"
  fi
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source /util.sh
  run_postupgrade "$@"
fi
