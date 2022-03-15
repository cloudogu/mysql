#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

wget https://dev.mysql.com/get/mysql-apt-config_0.8.18-1_all.deb
dpkg -i mysql-apt-config_0.8.18-1_all.deb <<EOF
1
1
mysql-5.7
ok
EOF
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 467B942D3A79BD29
apt update
# This will install mysql with empty root password
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install mysql-community-server