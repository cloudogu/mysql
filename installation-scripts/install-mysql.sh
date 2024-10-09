#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
DEBIAN_SHA_256_SUM="df9c563abd70bb9b2fb1be7d11868a300bd60023bcd60700f24430008059a704"
VERSION="0.8.32-1"
# see for latest version: https://dev.mysql.com/downloads/repo/apt/
wget "https://dev.mysql.com/get/mysql-apt-config_${VERSION}_all.deb"
echo "${DEBIAN_SHA_256_SUM} mysql-apt-config_${VERSION}_all.deb" | sha256sum -c -
# Select the correct mysql package
# 1. '1': Select the option to choose the mysql version
# 2. '3': Select mysql8.4-lts
# 3. 'ok': Finish configuration
dpkg -i "mysql-apt-config_${VERSION}_all.deb" <<EOF
1
3
ok
EOF
# https://repo.mysql.com/apt/ubuntu/conf/distributions
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 467B942D3A79BD29
apt-get update
# This will install mysql with empty root password
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install mysql-community-server
rm mysql-apt-config_${VERSION}_all.deb
