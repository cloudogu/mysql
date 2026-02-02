#!/bin/bash
set -euxo pipefail

MYSQL_MAJOR="$1"   # e.g. "8.4"

export DEBIAN_FRONTEND=noninteractive

APT_UTIL_VERSION="0.8.34-1"

# Download repo config
wget -q https://repo.mysql.com/mysql-apt-config_${APT_UTIL_VERSION}_all.deb
dpkg -i mysql-apt-config_${APT_UTIL_VERSION}_all.deb <<EOF
1
3
ok
EOF

# Update even if signatures are broken
apt-get update --allow-insecure-repositories || true

# Install latest available 8.4 LTS
apt-get install -y --allow-unauthenticated mysql-community-server

# Cleanup
rm -f mysql-apt-config_${APT_UTIL_VERSION}_all.deb
