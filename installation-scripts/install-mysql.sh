#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
DEBIAN_SHA_256_SUM="a62bca0a0fd67e11fd5c8efde7e67e6e59255c3f0fa61ecc817fd99254b483ab"
VERSION="0.8.29-1"
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
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys B7B3B788A8D3785C
apt-get update
# This will install mysql with empty root password
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install mysql-community-server
rm mysql-apt-config_${VERSION}_all.deb
