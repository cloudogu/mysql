# Sicherung und Wiederherstellung der MySQL durch Cloudogu EcoSystem Backup&Restore

Das MySQL-Dogu stellt jenen Konsumenten-Dogus zur Verfügung, die ihre Daten per SQL ablegen möchten. Mit Konsumenten-Dogu sind die Dogus gemeint, die MySQL als Abhängigkeit besitzen und die MySQL als Speicherung eigener Daten verwenden möchten. Jedes Konsumenten-Dogu erhält aus Sicherheitsgründen seine eigene Datenbank und die dazugehörigen Service-Account-Daten.

Die Daten innerhalb der MySQL werden auf zwei Arten gesichert. In beiden fällen wird die Sicherung auf dem Host der Cloudogu EcoSystem-Instanz durch `cesapp backup` gestartet.

Im ersten Fall sichert `cesapp` sämtliche MySQL-Daten -- inklusive aller Datenbanken aller Konsumenten-Dogus. 

Damit auch Sicherungen je Konsumenten-Dogu ermöglicht werden kann, kommt im zweiten Fall hierzu das `backup-consumer.sh`-Skript zum Tragen. Dieses Skript sorgt dafür, dass im Zuge der Sicherung lediglich die Datenbank eines des Konsumenten-Dogus abgezogen und gesichert wird, das seinerseits gerade gesichert wird.