#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

function run_preupgrade() {
  FROM_VERSION="${1}"
  TO_VERSION="${2}"

  if [ "${FROM_VERSION}" = "${TO_VERSION}" ]; then
    echo "FROM and TO versions are the same; Exiting..."
    exit 0
  fi

  if versionXLessOrEqualThanY "${FROM_VERSION}" "5.7.37-4" ; then
    if [[ -f "/var/lib/mysql/configured" &&  -f "/var/lib/mysql/prepared" ]]; then
      echo "=============================================================================================="
      echo "This was upgrade attempt 3: Starting the actual upgrade."
      echo "=============================================================================================="
      exit 0
    fi

    if [[ -f "/var/lib/mysql/configured" ]]; then
      sed -i 's/removeSocketIfExists/sleep\ infinity/' /startup.sh
      echo "=============================================================================================="
      echo "This was upgrade attempt 2: Mysql is now finally prepared for upgrade. Try again to start the upgrade."
      echo "=============================================================================================="
      touch "/var/lib/mysql/prepared"
      mysqladmin shutdown
    fi

    echo "innodb-fast-shutdown=0" >> /etc/my.cnf
    echo "innodb_force_recovery=1" >> /etc/my.cnf
    rm /var/lib/mysql/ib_logfile*
    touch /var/lib/mysql/configured

    echo "=============================================================================================="
    echo "This was upgrade attempt 1: Mysql was restarted. Redo upgrade attempt twice for a success."
    echo "=============================================================================================="

    mysqladmin shutdown
  fi

  echo "Mysql pre-upgrade done"
}

# versionXLessOrEqualThanY returns true if X is less than or equal to Y; otherwise false
function versionXLessOrEqualThanY() {
  local sourceVersion="${1}"
  local targetVersion="${2}"

  if [[ "${sourceVersion}" == "${targetVersion}" ]]; then
    return 0
  fi

  declare -r semVerRegex='([0-9]+)\.([0-9]+)\.([0-9]+)-([0-9]+)'

   sourceMajor=0
   sourceMinor=0
   sourceBugfix=0
   sourceDogu=0
   targetMajor=0
   targetMinor=0
   targetBugfix=0
   targetDogu=0

  if [[ ${sourceVersion} =~ ${semVerRegex} ]]; then
    sourceMajor=${BASH_REMATCH[1]}
    sourceMinor="${BASH_REMATCH[2]}"
    sourceBugfix="${BASH_REMATCH[3]}"
    sourceDogu="${BASH_REMATCH[4]}"
  else
    echo "ERROR: source dogu version ${sourceVersion} does not seem to be a semantic version"
    exit 1
  fi

  if [[ ${targetVersion} =~ ${semVerRegex} ]]; then
    targetMajor=${BASH_REMATCH[1]}
    targetMinor="${BASH_REMATCH[2]}"
    targetBugfix="${BASH_REMATCH[3]}"
    targetDogu="${BASH_REMATCH[4]}"
  else
    echo "ERROR: target dogu version ${targetVersion} does not seem to be a semantic version"
    exit 1
  fi

  if [[ $((sourceMajor)) -lt $((targetMajor)) ]] ; then
    return 0;
  fi
  if [[ $((sourceMajor)) -le $((targetMajor)) && $((sourceMinor)) -lt $((targetMinor)) ]] ; then
    return 0;
  fi
  if [[ $((sourceMajor)) -le $((targetMajor)) && $((sourceMinor)) -le $((targetMinor)) && $((sourceBugfix)) -lt $((targetBugfix)) ]] ; then
    return 0;
  fi
  if [[ $((sourceMajor)) -le $((targetMajor)) && $((sourceMinor)) -le $((targetMinor)) && $((sourceBugfix)) -le $((targetBugfix)) && $((sourceDogu)) -lt $((targetDogu)) ]] ; then
    return 0;
  fi

  return 1
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_preupgrade "$@"
fi

