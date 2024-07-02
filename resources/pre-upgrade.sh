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

  echo "Set registry flag so startup script waits for post-upgrade to finish..."
  doguctl config "local_state" "upgrading"

  dumpData

  echo "Mysql pre-upgrade done"
}

function dumpData(){
    TABLES="$(mysql -e "SELECT group_concat(schema_name) FROM information_schema.schemata WHERE schema_name NOT IN ('mysql', 'information_schema','performance_schema', 'sys');" | tail -n +2 | sed 's/,/ /g')"
    if [[ $TABLES == "NULL" ]]; then
      echo "TABLES are NULL. No available Data to DUMP."
      rm -rf /var/lib/mysql/*
      doguctl config --rm first_start_done
    else
      # shellcheck disable=SC2086 # Word splitting is intentional here
      mysqldump -u root --flush-privileges --opt --databases ${TABLES} > /alldb.sql

      local USERS
      USERS="$(mysql -uroot mysql -e "select GROUP_CONCAT(User) FROM user WHERE NOT User LIKE '%mysql.%' AND NOT User='root';" | tail -n +2 | sed 's/,/ /g')"

      local user
      for user in ${USERS}
      do
          local CREATE
          CREATE="$(mysql --skip-column-names -A mysql -e "SET @@SESSION.print_identified_with_as_hex = 1; SHOW CREATE USER '${user}'")"
          echo "${CREATE};" >> /alldb.sql
      done

      echo "flush privileges;" >> /alldb.sql

      mysql --skip-column-names -A -e"SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user<>''" | mysql --skip-column-names -A | sed 's/$/;/g' >> /alldb.sql
      rm -rf /var/lib/mysql/*
      doguctl config --rm first_start_done
      mv /alldb.sql /var/lib/mysql/alldb.sql
    fi
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

# versionXLessThanY returns true if X is less than Y; otherwise false
function versionXLessThanY() {
  if [[ "${1}" == "${2}" ]]; then
    return 1
  fi

  versionXLessOrEqualThanY "${1}" "${2}"
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_preupgrade "$@"
fi

