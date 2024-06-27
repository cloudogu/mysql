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

  if [[ -f "${WORKDIR}/var/lib/mysql/alldb.sql" ]]; then
    restoreDump
  fi

  echo "Set registry flag so startup script can start afterwards..."
  doguctl state "upgrade done"
  doguctl config --rm "local_state"

  echo "Mysql post-upgrade done"
}

restoreDump() {
  while [[ ! -f "${DATABASE_CONFIG_DIR}/default-config.cnf" ]]; do
    echo "Wait for preparations"
    sleep 3
  done

  mv "${WORKDIR}/var/lib/mysql/alldb.sql" "${WORKDIR}/alldb.sql"

  initializeMySql
  startMysqlInBackground

  echo "Reimport data from last version..."
  mysql -u root <"${WORKDIR}/alldb.sql"

  echo "Cleanup db..."
  rm -f "${WORKDIR}/var/lib/mysql/alldb.sql"

  echo "Shutdown mysql"
  mysqladmin shutdown
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source /util.sh
  run_postupgrade "$@"
fi
