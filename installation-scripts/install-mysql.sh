#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
# see for latest version: https://dev.mysql.com/downloads/repo/apt/
wget https://dev.mysql.com/get/mysql-apt-config_0.8.28-1_all.deb
# Select the correct mysql package
# 1. '1': Select the option to choose the mysql version
# 2. '1': Select mysql8.0
# 3. 'ok': Finish configuration
dpkg -i mysql-apt-config_0.8.28-1_all.deb <<EOF
1
1
ok
EOF
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 467B942D3A79BD29
apt-get update
# This will install mysql with empty root password
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install mysql-community-server
