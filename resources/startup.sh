#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

echo "                                     ./////,                    "
echo "                                 ./////==//////*                "
echo "                                ////.  ___   ////.              "
echo "                         ,**,. ////  ,////A,  */// ,**,.        "
echo "                    ,/////////////*  */////*  *////////////A    "
echo "                   ////'        \VA.   '|'   .///'       '///*  "
echo "                  *///  .*///*,         |         .*//*,   ///* "
echo "                  (///  (//////)**--_./////_----*//////)   ///) "
echo "                   V///   '°°°°      (/////)      °°°°'   ////  "
echo "                    V/////(////////\. '°°°' ./////////(///(/'   "
echo "                       'V/(/////////////////////////////V'      "

# shellcheck disable=SC1091
source "${STARTUP_DIR}/util.sh"

function runMain() {
  removeSocketIfExists
  renderConfigFile

  local state
  # Check staging first: post-upgrade creates the recovery directory before removing staging.
  until state="$(doguctl config local_state -d empty)" && [[ "${state}" == empty &&
    ! -d "${MYSQL_VOLUME}/.mysql-upgrade" && ! -d "${WORKDIR:-}/var/ces/config/mysql-upgrade" ]]; do
    echo "Waiting for confirmation that no MySQL upgrade is pending..."
    sleep 3
  done

  initializeMySql
  startMysql
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  runMain
fi
