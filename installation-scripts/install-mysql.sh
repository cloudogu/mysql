#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Base deps for repo + key
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

# Install MySQL repo signing key (current)
install -d -m 0755 /usr/share/keyrings
curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 \
  | gpg --dearmor \
  > /usr/share/keyrings/mysql.gpg

# Create a clean, valid repo file (Debian 12 = bookworm)
# NOTE: MySQL uses "mysql-8.4-lts" as component for 8.4 LTS in their APT repo config UI.
cat >/etc/apt/sources.list.d/mysql.list <<'EOF'
deb [signed-by=/usr/share/keyrings/mysql.gpg] http://repo.mysql.com/apt/debian bookworm mysql-8.4-lts
EOF

apt-get update

# Install server (root password empty behavior depends on packaging; noninteractive avoids prompts)
apt-get install -y --no-install-recommends mysql-community-server