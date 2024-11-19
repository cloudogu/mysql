# test for migrating a database with "mysql_native_password" plugin
cesapp purge mysql && cesapp install official/mysql 5.7.37-4 && cesapp start mysql
sleep 10s
cesapp command mysql service-account-create test && cesapp build .

