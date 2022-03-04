# Backup and restore behaviour MySQL during Cloudogu EcoSystem Backup&Restore.

The MySQL dogu provides those "consumer dogus" which want to store their data using SQL. A consumer dogu is a dogu that has MySQL as a dependency and wishes to use MySQL to store their data. For security reasons, each consumer dogu receives its own database and associated service account data. 

The data within MySQL is backed up in two ways. In both cases, the backup is started on the Cloudogu EcoSystem instance host by `cesapp backup`.

In the first case, `cesapp` backs up all MySQL data -- including all databases of all consumer dogus.

To enable backups per consumer dogu as well, the `backup-consumer.sh` script is used for this purpose in the second case. This script ensures that in the course of the backup only the database of one of the consumer dogus is extracted and backed up, which in turn is currently being backed up.