#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
DEBIAN_SHA_256_SUM="ea2370391967487e143ae7821b3ff65e6478e8fa9fb08ff3913bc43bdb2c6092"
VERSION="0.8.28-1"
# see for latest version: https://dev.mysql.com/downloads/repo/apt/
wget "https://dev.mysql.com/get/mysql-apt-config_${VERSION}_all.deb"
echo "${DEBIAN_SHA_256_SUM} mysql-apt-config_${VERSION}_all.deb" | sha256sum -c -
# Select the correct mysql package
# 1. '1': Select the option to choose the mysql version
# 2. '1': Select mysql8.0
# 3. 'ok': Finish configuration
dpkg -i "mysql-apt-config_${VERSION}_all.deb" <<EOF
1
1
ok
EOF
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 467B942D3A79BD29
apt-get update
# This will install mysql with empty root password
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install mysql-community-server
rm mysql-apt-config_${VERSION}_all.deb
