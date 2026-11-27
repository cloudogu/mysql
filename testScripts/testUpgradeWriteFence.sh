#!/bin/bash
# Run against the current Dogu in an isolated container with disposable data.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
image=$(docker build -q "$repo")
docker run --rm -i --network none --hostname mysql -e ECOSYSTEM_MULTINODE=true \
  --tmpfs /var/lib/mysql --tmpfs /var/ces/config -v "$repo/dogu.json:/descriptor.json:ro" \
  --entrypoint bash "$image" -seu <<'TEST'
mkdir -p /etc/ces/config/{normal,sensitive,global} /etc/ces/dogu_json/mysql /var/ces/state
printf fixture >/etc/ces/dogu_json/mysql/current
cp /descriptor.json /etc/ces/dogu_json/mysql/fixture
for group in normal sensitive global; do echo '{}' > "/etc/ces/config/$group/config.yaml"; done
echo '{}' >/var/ces/config/local.yaml
chown mysql:mysql /var/lib/mysql

wait_for_mysql() { timeout 60 bash -c 'until mysql -Nse "SELECT 1" >/dev/null 2>&1; do sleep .2; done'; }
rows() { mysql -uwriter -Nse 'SELECT GROUP_CONCAT(id ORDER BY id) FROM smoke.t'; }
trap 'tail /tmp/startup.log >&2' ERR
/startup.sh >/tmp/startup.log 2>&1 & server=$!
wait_for_mysql
mysql -e "CREATE DATABASE smoke; CREATE TABLE smoke.t (id INT PRIMARY KEY); CREATE USER 'writer'@'%'; GRANT INSERT, SELECT ON smoke.* TO 'writer'@'%';"
mysql -uwriter -e 'INSERT INTO smoke.t VALUES (17)'
/pre-upgrade.sh 8.4.13-1 8.4.13-2 </dev/null
late_status=0
late_error=$(mysql -uwriter -e 'INSERT INTO smoke.t VALUES (93)' 2>&1) || late_status=$?
echo "Late insert: status=$late_status $late_error; source rows: $(rows)"
mysqladmin shutdown
wait "$server"

# The source and target use the same image and rendered config in this fixture.
/post-upgrade.sh 8.4.13-1 8.4.13-2 </dev/null
/startup.sh >/tmp/startup.log 2>&1 & server=$!
wait_for_mysql
restored=$(rows)
echo "Rows after restore: $restored"
[[ $late_status != 0 && $late_error == *'ERROR 1290 '* && $restored == 17 ]]
mysql -uwriter -e 'INSERT INTO smoke.t VALUES (93)'
final=$(rows)
echo "Rows after retry on the target: $final"
[[ $final == 17,93 ]]
mysqladmin shutdown
wait "$server"
TEST
