[mysqld]

# the working set in innodb_buffer_pool_size should take up to 80 % of the memory
# but at least 512 MB should be used (recommended settings vary from 2 to 16 GB depending on the actual DB server load)
# see https://wiki.alpinelinux.org/wiki/Production_DataBases_:_mysql
innodb_buffer_pool_size={{ .Env.Get "INNODB_BUFFER_POOL_SIZE_IN_BYTES"}}
innodb_log_file_size=16M

# The Performance Schema is a feature for monitoring server performance in which the DB server populates internal tables with said monitoring data.
# see https://dev.mysql.com/doc/refman/5.7/en/performance-schema-startup-configuration.html
performance_schema = OFF

# recommended settings by Alpine
# see https://wiki.alpinelinux.org/wiki/Production_DataBases_:_mysql
max_connections=100
max_heap_table_size=32M
tmp_table_size=32M
innodb_read_io_threads=32

# Size in bytes for which results larger than this are not stored in the query cache.
# see: https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_query_cache_limit
query_cache_limit=2M

# This will improve performance as short queries are not logged to the slow query log
# see: https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_min_examined_row_limit
min_examined_row_limit         = 100

innodb_file_format              = BARRACUDA
# See: https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_query_cache_type
query_cache_type                = 1
# See: https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_query_cache_size
query_cache_size                = 60M

# See: https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_sort_buffer_size
sort_buffer_size                = 5M
# See: https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_read_buffer_size
read_buffer_size                = 1M
# See: https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_join_buffer_size
join_buffer_size                = 1M

# See: https://dev.mysql.com/doc/refman/5.7/en/innodb-auto-increment-handling.html
innodb_autoinc_lock_mode        = 2
# See: https://dev.mysql.com/doc/refman/8.0/en/innodb-parameters.html#sysvar_innodb_flush_log_at_trx_commit
innodb_flush_log_at_trx_commit  = 2

# Set bind address for mysqld
bind-address = 0.0.0.0

[mysqldump]
# Increase max_allowed_packet size
# see: https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_max_allowed_packet
max_allowed_packet              = 200M
add_drop_table                  = True
