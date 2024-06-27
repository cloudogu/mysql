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

  while [[ "$(doguctl config "local_state" -d "empty")" == "upgrading" ]]; do
    echo "Upgrade script is running. Waiting..."
    sleep 3
  done

  initializeMySql
  startMysql
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  runMain
fi
