#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

DEBIAN_SHA_256_SUM="df9c563abd70bb9b2fb1be7d11868a300bd60023bcd60700f24430008059a704"
VERSION="0.8.32-1"

export DEBIAN_FRONTEND=noninteractive

# prerequisites
apt-get update
apt-get install -y wget ca-certificates gnupg

# install MySQL signing key (CURRENT)
mkdir -p /usr/share/keyrings
wget -qO- https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 \
  | gpg --dearmor \
  > /usr/share/keyrings/mysql.gpg

# download mysql repo config
wget "https://dev.mysql.com/get/mysql-apt-config_${VERSION}_all.deb"
echo "${DEBIAN_SHA_256_SUM} mysql-apt-config_${VERSION}_all.deb" | sha256sum -c -

# configure mysql repo (mysql 8.4 LTS)
dpkg -i "mysql-apt-config_${VERSION}_all.deb" <<EOF
1
3
ok
EOF

# ensure repo uses the keyring
sed -i 's|^deb |deb [signed-by=/usr/share/keyrings/mysql.gpg] |' \
  /etc/apt/sources.list.d/mysql.list

# update & install
apt-get update
apt-get -y install mysql-community-server

# cleanup
rm -f mysql-apt-config_${VERSION}_all.deb
