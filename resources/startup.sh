#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

function runMain() {
  mysqld || (true && sleep infinity && echo "FAILURE")
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  runMain
fi
