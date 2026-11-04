#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

MYSQL_VERSION="${1}"
# MySQL apt repo component of the LTS series MYSQL_VERSION belongs to, e.g. 1.2.3 -> mysql-1.2-lts
MYSQL_APT_COMPONENT="mysql-${MYSQL_VERSION%.*}-lts"
# Debian release of the base image
DEBIAN_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
DEBIAN_VERSION_ID="$(. /etc/os-release && echo "${VERSION_ID}")"
MYSQL_PACKAGE_VERSION="${MYSQL_VERSION}-1debian${DEBIAN_VERSION_ID}"

# Version of debian file containing the installation files for mysql in different versions
# This is NOT the actual mysql version to install
APT_UTIL_VERSION="0.8.36-1"
APT_UTIL_SHA256="4d7db2369b1430152eb46cfa35e2576ea32fdbbb6501cbab8261654b8fbb6234"

# See for latest version: https://dev.mysql.com/downloads/repo/apt/
wget "https://dev.mysql.com/get/mysql-apt-config_${APT_UTIL_VERSION}_all.deb"
echo "${APT_UTIL_SHA256} mysql-apt-config_${APT_UTIL_VERSION}_all.deb" | sha256sum -c -

# Install the apt config package non-interactively and preselect the MySQL LTS series.
DEBIAN_FRONTEND=noninteractive MYSQL_SERVER_VERSION="${MYSQL_APT_COMPONENT}" \
  dpkg -i "mysql-apt-config_${APT_UTIL_VERSION}_all.deb"

# --- Non-deprecated key setup: /etc/apt/keyrings + signed-by ---
install -d -m 0755 /etc/apt/keyrings

# MySQL publishes the current repo key as RPM-GPG-KEY-mysql-2025 on repo.mysql.com :contentReference[oaicite:1]{index=1}
wget -qO- https://repo.mysql.com/RPM-GPG-KEY-mysql-2025 \
  | gpg --dearmor -o /etc/apt/keyrings/mysql.gpg

tee /etc/apt/sources.list.d/mysql.list >/dev/null <<EOF
deb [signed-by=/etc/apt/keyrings/mysql.gpg] https://repo.mysql.com/apt/debian/ ${DEBIAN_CODENAME} ${MYSQL_APT_COMPONENT}
deb-src [signed-by=/etc/apt/keyrings/mysql.gpg] https://repo.mysql.com/apt/debian/ ${DEBIAN_CODENAME} ${MYSQL_APT_COMPONENT}
EOF

apt-get update

if ! apt-cache madison mysql-server | grep -q "${MYSQL_PACKAGE_VERSION}"; then
  echo "ERROR: MySQL version ${MYSQL_PACKAGE_VERSION} not available in APT repo."
  exit 42
fi

# This will install mysql with empty root password
export DEBIAN_FRONTEND=noninteractive
apt-get -y install "mysql-community-server=${MYSQL_PACKAGE_VERSION}"
rm -f "mysql-apt-config_${APT_UTIL_VERSION}_all.deb"
