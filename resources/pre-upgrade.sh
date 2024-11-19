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

  dumpData "${FROM_VERSION}" "${TO_VERSION}"

  echo "Mysql pre-upgrade done"
}

function dumpData(){
    FROM_VERSION="${1}"
    TO_VERSION="${2}"

    TABLES="$(mysql -e "SELECT group_concat(schema_name) FROM information_schema.schemata WHERE schema_name NOT IN ('mysql', 'information_schema','performance_schema', 'sys');" | tail -n +2 | sed 's/,/ /g')"
    if [[ "${TABLES}" == "NULL" ]]; then
      echo "TABLES are NULL. No available Data to DUMP."
      rm -rf /var/lib/mysql/*
      doguctl config --rm first_start_done
    else
      # shellcheck disable=SC2086 # Word splitting is intentional here
      mysqldump -u root --flush-privileges --opt --databases ${TABLES} > /alldb.sql

      local DEPRECATED_PLUGIN
      DEPRECATED_PLUGIN="$(mysql -uroot mysql -e "select count(*) FROM user WHERE plugin LIKE 'mysql_native_password';" | tail -n +2)"

      if [[ "${DEPRECATED_PLUGIN}" -gt "0" ]]; then
        TO_MAJOR_VERSION=$(echo "${TO_VERSION}" | cut -d '.' -f1)
        TO_MINOR_VERSION=$(echo "${TO_VERSION}" | cut -d '.' -f2)
        # Update to 8.4
        if [[ "${TO_MAJOR_VERSION}" == "8" && "${TO_MINOR_VERSION}" -ge "4" ]]; then
          echo "WARNING: ⚠️ database contains deprecated password hashes with 'mysql_native_password' plugin - this plugin is deprecated and should be removed"
        fi
        # Update to 9.x
        if [[ "${TO_MAJOR_VERSION}" -ge "9" ]]; then
          echo "ERROR: ❌ database contains invalid password hashes with 'mysql_native_password' plugin - this plugin is deactivated in mysql 9 and above"
          exit 1
        fi
      fi

      local USERS
      USERS="$(mysql -uroot mysql -e "select GROUP_CONCAT(User) FROM user WHERE NOT User LIKE '%mysql.%' AND NOT User='root';" | tail -n +2 | sed 's/,/ /g')"

      # as users may exists within the dump but need to be recreated with all privileges the user must be dropped first
      # otherwise the creation would result in an ERROR 1396 (HY000) - see https://stackoverflow.com/a/6332971
      if [[ "${USERS}" != "NULL" ]]; then
        local user
        for user in ${USERS}
        do
            echo "DROP user IF EXISTS '${user}';" >> /alldb.sql
        done

        # flush privileges just once instead of once per user
        echo "flush privileges;" >> /alldb.sql

        FROM_MAJOR_VERSION=$(echo "${FROM_VERSION}" | cut -d '.' -f1)

        # recreate users
        for user in ${USERS}
        do
            local CREATE
            local PRINT_HEX
            PRINT_HEX=""
            if [[ ${FROM_MAJOR_VERSION} -ge 8 ]]; then
              PRINT_HEX="SET @@SESSION.print_identified_with_as_hex = 1; "
            fi
            CREATE="$(mysql --skip-column-names -A mysql -e "${PRINT_HEX}SHOW CREATE USER '${user}'")"
            echo "${CREATE};" >> /alldb.sql
        done

        echo "flush privileges;" >> /alldb.sql

        local GRANT
        GRANT="$(mysql --skip-column-names -A -e"SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user<>''" | mysql --skip-column-names -A | sed 's/$/;/g')"

        # this is needed for any version from 8.4 and up
        # SET_USER_ID Privilege was removed as deprecated
        # https://dev.mysql.com/doc/refman/8.4/en/mysql-nutshell.html
        GRANT=$(echo "${GRANT}" |  sed 's/SET_USER_ID,/SET_ANY_DEFINER,ALLOW_NONEXISTENT_DEFINER,/g')

        echo "${GRANT};" >> /alldb.sql
      fi

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

