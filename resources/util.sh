#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

DATABASE_CONFIG_DIR="${STARTUP_DIR}/etc/my.cnf.dogu.d"

function renderConfigFile() {
  echo "Rendering config file..."
  mkdir -p "${DATABASE_CONFIG_DIR}"
  INNODB_BUFFER_POOL_SIZE_IN_BYTES="$(calculateInnoDbBufferPoolSize)"
  export INNODB_BUFFER_POOL_SIZE_IN_BYTES
  echo "Setting innodb_buffer_pool_size to ${INNODB_BUFFER_POOL_SIZE_IN_BYTES} bytes"

  doguctl template "${STARTUP_DIR}/default-config.cnf.tpl" "${DATABASE_CONFIG_DIR}/default-config.cnf"
}

# cgroup files holding the container memory limit (v2, fallback v1); can be overridden in tests
CGROUP_V2_MEMORY_LIMIT_FILE="${CGROUP_V2_MEMORY_LIMIT_FILE:-/sys/fs/cgroup/memory.max}"
CGROUP_V1_MEMORY_LIMIT_FILE="${CGROUP_V1_MEMORY_LIMIT_FILE:-/sys/fs/cgroup/memory/memory.limit_in_bytes}"

function calculateInnoDbBufferPoolSize() {
  defaultInnoDbBufferPool512M="512M"
  memoryLimitInBytes=$(cat "${CGROUP_V2_MEMORY_LIMIT_FILE}" 2>/dev/null || cat "${CGROUP_V1_MEMORY_LIMIT_FILE}" 2>/dev/null || true)

  # no limit: no cgroup file, "max" (cgroup v2) or ~8 EiB (cgroup v1)
  if ! [[ ${memoryLimitInBytes} =~ ^[0-9]+$ ]] || [[ ${memoryLimitInBytes} -gt 549755813888 ]]; then
    echo "${defaultInnoDbBufferPool512M}"
    return
  fi

  # largest power of two that is at most half of the limit (at least 128 MiB);
  # powers of two are whole multiples of MySQL's chunk size, so MySQL does not round them up
  bufferPoolSize=$((128 * 1048576))
  while [[ $((bufferPoolSize * 4)) -le ${memoryLimitInBytes} ]]; do
    bufferPoolSize=$((bufferPoolSize * 2))
  done

  echo "${bufferPoolSize}"
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
  currentLogLevel=$(doguctl config --default "WARN" "logging/root")

  case "${currentLogLevel}" in
    "ERROR")
      DOGU_LOGLEVEL=1
    ;;
    "INFO")
      DOGU_LOGLEVEL=3
    ;;
    "DEBUG")
      DOGU_LOGLEVEL=3
    ;;
    *)
      DOGU_LOGLEVEL=2
    ;;
  esac
}

function initializeMySql() {
  FIRST_START_DONE="$(doguctl config first_start_done --default "NO")"

  if [ "${FIRST_START_DONE}" == "NO" ]; then
    echo "Initialize Mysql..."
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
  if [[ "$(doguctl config "local_state" -d "empty")" != "empty" ]]; then
    doguctl config --rm "local_state"
  fi
  runuser -u mysql -- mysqld  --datadir="${MYSQL_VOLUME}" --log_error_verbosity=${DOGU_LOGLEVEL}
}

function startMysqlInBackground() {
  echo "Starting mysql in background..."
  echo "${MYSQL_VOLUME}"
  runuser -u mysql -- mysqld  --datadir="${MYSQL_VOLUME}" &

  while [[ "$(mysql -e "show databases;" &> /dev/null; echo $?)" == "1" ]]; do
    echo "Waiting for mysql to start..."
    sleep 3
  done
  sleep 20
}

function removeSocketIfExists(){
  echo "Removing mysql lockfile if existing..."
  rm -f "${STARTUP_DIR}/var/run/mysqld/mysqld.sock.lock"
  rm -f "${STARTUP_DIR}/var/run/mysqld/mysqld.sock"
}
