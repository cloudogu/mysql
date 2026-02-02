#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

# Install CURRENT MySQL signing key
install -d /usr/share/keyrings
curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 \
  | gpg --dearmor \
  > /usr/share/keyrings/mysql.gpg

# Add MySQL 8.4 LTS repo explicitly
cat >/etc/apt/sources.list.d/mysql.list <<'EOF'
deb [signed-by=/usr/share/keyrings/mysql.gpg] http://repo.mysql.com/apt/debian bookworm mysql-8.4-lts
EOF

apt-get update
apt-get install -y mysql-community-server
