#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

DATABASE_CONFIG_DIR="/etc/my.cnf.dogu.d"

function renderConfigFile() {
  echo "Rendering config file..."

  INNODB_BUFFER_POOL_SIZE_IN_BYTES="$(calculateInnoDbBufferPoolSize)"
  export INNODB_BUFFER_POOL_SIZE_IN_BYTES
  echo "Setting innodb_buffer_pool_size to ${INNODB_BUFFER_POOL_SIZE_IN_BYTES} bytes"

  mkdir -p "${DATABASE_CONFIG_DIR}"
  doguctl template "/default-config.cnf.tpl" "${DATABASE_CONFIG_DIR}/default-config.cnf"
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

function initializeMySql() {
  FIRST_START_DONE="$(doguctl config first_start_done --default "NO")"

  if [ "${FIRST_START_DONE}" == "NO" ]; then
    mysqld --initialize-insecure
    doguctl config first_start_done --default "YES"
  fi
}