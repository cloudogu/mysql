#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

function run_preupgrade() (
  FROM_VERSION="${1}"
  TO_VERSION="${2}"

  if [ "${FROM_VERSION}" = "${TO_VERSION}" ]; then
    echo "FROM and TO versions are the same; Exiting..."
    exit 0
  fi

  # Older Dogu versions only mount the data volume. Leave the original data
  # intact until post-upgrade has copied the dump out of the data directory.
  local data_volume="${MYSQL_VOLUME:-/var/lib/mysql}"
  if ! mountpoint -q "${data_volume}"; then
    echo "ERROR: MySQL data volume ${data_volume} is not mounted" >&2
    return 1
  fi
  local dump_dir="${data_volume}/.mysql-upgrade"
  install -d -m 700 "${dump_dir}"
  exec 9>>"${dump_dir}/export.lock"
  if ! flock -n 9; then
    echo "ERROR: Another MySQL export is running" >&2
    return 1
  fi
  # With no other export running, reclaim files left by an interrupted attempt.
  find "${dump_dir}" -mindepth 2 -maxdepth 2 -type f -name alldb.partial -delete
  find "${dump_dir}" -mindepth 1 -maxdepth 1 -type d -empty -delete

  local state dump_id attempt_dir read_only
  local versions="${FROM_VERSION} ${TO_VERSION}"
  state="$(doguctl config local_state -d empty)"
  dump_id="$(doguctl config upgrade_dump_id -d none)"
  attempt_dir="${dump_dir}/${dump_id}"
  if [[ "${state}" == upgrading && "${dump_id}" =~ ^[a-zA-Z0-9]{12}$ && -f "${attempt_dir}/alldb.sql" &&
        -f "${attempt_dir}/versions" && "$(<"${attempt_dir}/versions")" == "${versions}" ]]; then
    read_only="$(mysql -uroot -NBe 'SELECT @@GLOBAL.super_read_only')"
    if [[ "${read_only}" == 1 ]]; then
      # The previous hook may have stopped between the rename and its sync.
      sync -f "${attempt_dir}"
      echo "Reusing completed MySQL export ${dump_id}"
      return 0
    fi
  fi

  attempt_dir="$(mktemp -d "${dump_dir}/XXXXXXXXXXXX")"
  trap 'rm -f -- "${attempt_dir}/alldb.partial"' EXIT
  # Publish the expected identity first, but only publish the SQL file after a successful dump.
  doguctl config upgrade_dump_id "${attempt_dir##*/}"
  doguctl config local_state upgrading
  install -m 600 /dev/null "${attempt_dir}/alldb.partial"
  fenceSourceWrites "${FROM_VERSION}" "${data_volume}"
  dumpData "${FROM_VERSION}" "${TO_VERSION}" "${attempt_dir}/alldb.partial"
  printf '%s\n' "${versions}" > "${attempt_dir}/versions"
  # A replay must never see the completed name with only part of the SQL on disk.
  sync -d "${attempt_dir}/alldb.partial" "${attempt_dir}/versions"
  mv "${attempt_dir}/alldb.partial" "${attempt_dir}/alldb.sql"
  sync -f "${attempt_dir}"

  echo "Mysql pre-upgrade done"
)

fenceSourceWrites() {
  local source_version="$1" data_volume="$2"
  echo 'Making the source MySQL server read-only until cutover...'
  if [[ "${source_version}" == 5.7.* ]]; then
    # 5.7 has no SET PERSIST. Its Dogu runs mysqld as mysql with the data volume as its home.
    local guard="${data_volume}/.mysql-upgrade/source-read-only.cnf" options="${data_volume}/.my.cnf"
    if [[ ! "${guard}" -ef "${options}" ]]; then
      printf '[mysqld]\nsuper_read_only=ON\n' > "${guard}"
      chmod 644 "${guard}"
      # Do not replace an operator's option file. The hard link also survives container replacement.
      ln -T "${guard}" "${options}"
    fi
    sync -f "${data_volume}"
    mysql -uroot -e 'SET GLOBAL super_read_only = ON'
  else
    if [[ "$(mysql -uroot -NBe 'SELECT @@GLOBAL.persisted_globals_load')" != 1 ]]; then
      echo 'ERROR: Cannot guarantee a read-only source after restart without persisted globals' >&2
      return 1
    fi
    mysql -uroot -e 'SET PERSIST super_read_only = ON'
  fi
}

function dumpData(){
    FROM_VERSION="${1}"
    TO_VERSION="${2}"
    local dump_file="${3}"

    TABLES="$(mysql -e "SELECT group_concat(schema_name) FROM information_schema.schemata WHERE schema_name NOT IN ('mysql', 'information_schema','performance_schema', 'sys');" | tail -n +2 | sed 's/,/ /g')"
    if [[ "${TABLES}" == "NULL" ]]; then
      echo "TABLES are NULL. No available Data to DUMP."
    else
      # shellcheck disable=SC2086 # Word splitting is intentional here
      mysqldump -u root --flush-privileges --opt --databases ${TABLES} > "${dump_file}"
      if [[ ! -s "${dump_file}" ]]; then
        echo "ERROR: MySQL returned an empty dump for existing schemas" >&2
        return 1
      fi

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
            echo "DROP user IF EXISTS '${user}';" >> "${dump_file}"
        done

        # flush privileges just once instead of once per user
        echo "flush privileges;" >> "${dump_file}"

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
            echo "${CREATE};" >> "${dump_file}"
        done

        echo "flush privileges;" >> "${dump_file}"

        local GRANT
        GRANT="$(mysql --skip-column-names -A -e"SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user<>''" | mysql --skip-column-names -A | sed 's/$/;/g')"

        # this is needed for any version from 8.4 and up
        # SET_USER_ID Privilege was removed as deprecated
        # https://dev.mysql.com/doc/refman/8.4/en/mysql-nutshell.html
        GRANT=$(echo "${GRANT}" |  sed 's/SET_USER_ID,/SET_ANY_DEFINER,ALLOW_NONEXISTENT_DEFINER,/g')

        echo "${GRANT};" >> "${dump_file}"
      fi
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
