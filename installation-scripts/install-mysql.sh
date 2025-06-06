#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

MYSQL_VERSION="${1}"

# Version of debian file containing the installation files for mysql in different versions
# This is NOT the actual mysql version to install
APT_UTIL_VERSION="0.8.34-1"
APT_UTIL_SHA256="9a7b0d074e7854725de10af2fdfccfba5749fd0f3c2d89b3529ee2e4035cc217"

# See for latest version: https://dev.mysql.com/downloads/repo/apt/
wget "https://dev.mysql.com/get/mysql-apt-config_${APT_UTIL_VERSION}_all.deb"
echo "${APT_UTIL_SHA256} mysql-apt-config_${APT_UTIL_VERSION}_all.deb" | sha256sum -c -

# Select the correct mysql package
# 1. '1': Select the option to choose the mysql version
# 2. '3': Select mysql8.4-lts
# 3. 'ok': Finish configuration
dpkg -i "mysql-apt-config_${APT_UTIL_VERSION}_all.deb" <<EOF
1
3
ok
EOF

# Fetch signing key for package verification
# https://repo.mysql.com/apt/ubuntu/conf/distributions
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 467B942D3A79BD29
apt-get update

# This will install mysql with empty root password
export DEBIAN_FRONTEND=noninteractive
apt-get -y install "mysql-community-server=${MYSQL_VERSION}-1debian12"
rm -f "mysql-apt-config_${APT_UTIL_VERSION}_all.deb"
