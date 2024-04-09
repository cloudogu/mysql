#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

wget https://dev.mysql.com/get/mysql-apt-config_0.8.18-1_all.deb
# Select the correct mysql package
# 1. '1': Select operating system 'debian buster'
# 2. '1': Select the option to choose the mysql version
# 3. '2': Select mysql8.0
# 4. 'ok': Finish configuration
dpkg -i mysql-apt-config_0.8.18-1_all.deb <<EOF
1
1
2
ok
EOF
# https://repo.mysql.com/apt/ubuntu/conf/distributions
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys B7B3B788A8D3785C
apt update
# This will install mysql with empty root password
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install mysql-community-server
