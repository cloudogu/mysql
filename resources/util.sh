#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

DATABASE_CONFIG_DIR="${STARTUP_DIR}/etc/my.cnf.dogu.d"

function renderConfigFile() {
  echo "Rendering config file..."

  INNODB_BUFFER_POOL_SIZE_IN_BYTES="$(calculateInnoDbBufferPoolSize)"
  export INNODB_BUFFER_POOL_SIZE_IN_BYTES
  echo "Setting innodb_buffer_pool_size to ${INNODB_BUFFER_POOL_SIZE_IN_BYTES} bytes"

  doguctl template "${STARTUP_DIR}/default-config.cnf.tpl" "${DATABASE_CONFIG_DIR}/default-config.cnf"
}

function calculateInnoDbBufferPoolSize() {
  defaultInnoDbBufferPool512M="512M"
  memoryLimitFromEtcd=$(doguctl config "container_config/memory_limit" -d "empty")
  if [[ "${memoryLimitFromEtcd}" == "empty" ]]; then
      echo "${defaultInnoDbBufferPool512M}"
      return
  fi

  local memoryLimitExitCode=0
  memoryLimitInBytes=$(cat < "${CONTAINER_MEMORY_LIMIT_FILE}" | tr -d '\n') || memoryLimitExitCode=$?
  if [[ memoryLimitExitCode -ne 0 ]]; then
    logError "Error while receiving container memory limit: Exit code: ${memoryLimitExitCode}. Falling back to ${defaultInnoDbBufferPool512M} MB."

    echo "${defaultInnoDbBufferPool512M}"
    return
  fi

  if ! [[ ${memoryLimitInBytes} =~ ^[0-9]+$ ]] ; then
    logError "Memory limit file does not contain a number (found: ${memoryLimitInBytes}). Falling back to ${defaultInnoDbBufferPool512M} MB."

    echo "${defaultInnoDbBufferPool512M}"
    return
  fi

  if [[ ${memoryLimitInBytes} -lt 536870912 ]]; then
    echo "${defaultInnoDbBufferPool512M}"
    return
  fi

  if [[ ${memoryLimitInBytes} -gt 549755813888 ]]; then
    logError "Detected a memory limit of > 512 GB! Was 'memory_limit' set without re-creating the container?"
  fi

  innoDbBufferPool80percent=$(echo "${memoryLimitInBytes} * 80 / 100" | bc) || memoryLimitExitCode=$?
  if [[ memoryLimitExitCode -ne 0 ]]; then
    logError "Error while calculating memory limit: Exit code: ${memoryLimitExitCode}. Falling back to ${defaultInnoDbBufferPool512M} MB."

    echo "${defaultInnoDbBufferPool512M}"
    return
  fi

  echo "${innoDbBufferPool80percent}"
  return
}

function applySecurityConfiguration() {
  echo "Applying security configuration..."

  # wait until mariadb is ready to accept connections
  doguctl wait --port 3306

  # remove remote root
  mysql -uroot -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"

  # secure the installation
  # https://github.com/twitter-forks/mysql/blob/master/scripts/mysql_secure_installation.sh
  mysql -uroot -e "DROP DATABASE test;"
  mysql -uroot -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

  # remove anonymous user
  mysql -uroot -e "DELETE FROM mysql.user WHERE User='';"

  # reload privilege tables
  mysql -uroot -e "FLUSH PRIVILEGES;"
}

function setDoguLogLevel() {
  currentLogLevel=$(doguctl config --default "ERROR" "logging/root")

  case "${currentLogLevel}" in
    "WARN")
      DOGU_LOGLEVEL=2
    ;;
    "INFO")
      DOGU_LOGLEVEL=3
    ;;
    "DEBUG")
      DOGU_LOGLEVEL=9
    ;;
    *)
      DOGU_LOGLEVEL=1
    ;;
  esac
}

function initializeMySql() {
  FIRST_START_DONE="$(doguctl config first_start_done --default "NO")"

  if [ "${FIRST_START_DONE}" == "NO" ]; then
    mysqld --initialize-insecure
    doguctl config first_start_done "YES"
  fi
}

function logError() {
  errMsg="${1}"

  >&2 echo "ERROR: ${errMsg}"
}

function startMysql() {
  echo "Starting mysql..."
  setDoguLogLevel
  doguctl state "ready"
  mysqld --datadir="${MYSQL_VOLUME}" --log-warnings="${DOGU_LOGLEVEL}"
  mysqld --user=mysql
}