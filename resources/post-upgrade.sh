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
  if ! mountpoint -q "${config_volume}"; then
    echo "ERROR: Upgrade dump volume ${config_volume} is not mounted" >&2
    return 1
  fi
  if ! mountpoint -q "${MYSQL_VOLUME}"; then
    echo "ERROR: MySQL data volume ${MYSQL_VOLUME} is not mounted" >&2
    return 1
  fi

  local staging_dir="${MYSQL_VOLUME}/.mysql-upgrade"
  local recovery_dir="${config_volume}/mysql-upgrade"
  local state dump_id
  state="$(doguctl config local_state -d empty)"
  dump_id="$(doguctl config upgrade_dump_id -d none)"
  if [[ "${dump_id}" == none && "${state}" != upgrading && ! -d "${staging_dir}" && ! -d "${recovery_dir}" ]]; then
    return 0
  fi
  if [[ ! "${dump_id}" =~ ^[a-zA-Z0-9]{12}$ ]]; then
    echo "ERROR: Missing or invalid upgrade dump ID; refusing to restore" >&2
    return 1
  fi

  # A retry may use only this export's files, even for the same version pair.
  local dump_dir="${recovery_dir}/${dump_id}"
  local staged_dump="${staging_dir}/${dump_id}/alldb.sql"
  local dump_file="${dump_dir}/alldb.sql"
  if [[ -d "${staging_dir}" && ! -f "${staged_dump}" ]]; then
    echo "ERROR: Data volume has no completed export for upgrade ${dump_id}" >&2
    return 1
  fi
  if [[ -d "${recovery_dir}" ]]; then
    local other_attempt
    other_attempt="$(find "${recovery_dir}" -mindepth 1 -maxdepth 1 ! -name "${dump_id}" -print -quit)"
    if [[ -n "${other_attempt}" ]]; then
      echo "ERROR: Unrelated recovery files in ${recovery_dir}; refusing to restore" >&2
      return 1
    fi
  fi

  if [[ -f "${dump_dir}/imported.sql" ]]; then
    # The import has finished; only the final status or cleanup may be pending.
    if [[ -f "${staged_dump}" || -f "${dump_file}" ]]; then
      echo "ERROR: Found both a completed and a pending restore; refusing to finish upgrade" >&2
      return 1
    fi
    if [[ -d "${dump_dir}/restoring" ]]; then
      rmdir "${dump_dir}/restoring"
    fi
  elif [[ "${state}" != "upgrading" ]]; then
    if [[ -d "${staging_dir}" || -f "${dump_file}" || -d "${dump_dir}/restoring" ]]; then
      echo "ERROR: Pending upgrade dump without upgrade state; refusing to restore" >&2
      return 1
    fi
  else
    install -d -m 700 "${recovery_dir}" "${dump_dir}"
    if ! mkdir "${dump_dir}/restoring"; then
      echo "ERROR: Previous restore did not stop cleanly; inspect ${dump_dir} before retrying" >&2
      return 1
    fi
    if ! prepareRecoveryDump "${staged_dump}" "${dump_dir}"; then
      rm -f "${dump_dir}/alldb.partial"
      # A failed sync can leave a full-sized copy. Free it only if staging still holds the dump.
      if [[ -f "${staged_dump}" ]]; then
        rm -f "${dump_file}"
      fi
      rmdir "${dump_dir}/restoring"
      return 1
    fi

    # MySQL initialization ignores dotfiles. Remove only the ones created by the upgrade.
    local options="${MYSQL_VOLUME}/.my.cnf"
    if [[ ! -L "${options}" && "${options}" -ef "${staging_dir}/source-read-only.cnf" ]]; then
      rm -- "${options}"
    fi
    find "${MYSQL_VOLUME}" -mindepth 1 -maxdepth 1 \( ! -name '.*' -o -name '.mysql-upgrade' \) -exec rm -rf -- {} +
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
  # Startup also waits for the recovery directory to disappear.
  rm -f "${dump_dir}/imported.sql"
  if [[ -d "${dump_dir}" ]]; then
    rmdir "${dump_dir}"
  fi
  if [[ -d "${recovery_dir}" ]]; then
    rmdir "${recovery_dir}"
  fi
  # A crash must not bring back recovery files after the registry forgets their ID.
  sync -f "${config_volume}"
  doguctl config --rm upgrade_dump_id

  echo "Mysql post-upgrade done"
}

prepareRecoveryDump() {
  local staged_dump="$1" dump_dir="$2"
  if [[ -f "${staged_dump}" ]]; then
    cp "${staged_dump}" "${dump_dir}/alldb.partial" || return 1
    mv "${dump_dir}/alldb.partial" "${dump_dir}/alldb.sql" || return 1
  elif [[ ! -f "${dump_dir}/alldb.sql" ]]; then
    echo "ERROR: Expected upgrade dump is missing; refusing to initialize MySQL" >&2
    return 1
  fi
  sync -f "${dump_dir}"
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
