# Konfiguration des MySQL-Dogu

## Voraussetzung

* MySQL ist erfolgreich [installiert](Install_Dogu_de.md)

## Konfigurationsmöglichkeiten

Das MySQL-Dogu wird über die Registry konfiguriert.
Es gibt mehrere Möglichkeiten, um Werte in der Registry zu konfigurieren.
Kurzgefasst kann man:
1. Ein Dogu mit `kubectl edit configmap mysql-config` konfigurieren (empfohlen)
2. Die Konfigurationswerte mithilfe eines Blueprint aktualisieren

## Konfiguration

MySQL bietet die folgenden Einstellungen:

#### Logging-Verhalten
* Konfigurationsschlüssel-Pfad: `logging/root`
* Inhalt: Verändert das Logging-Verhalten des MySQL-Docker-Containers. Dieser Wert wird erst nach dem Container-Neustart aktiv.
* Datentyp: String
* Valide Werte: ERROR, WARN, INFO, DEBUG
* Standardwert: ERROR
* Siehe [logging_de.md](logging_de.md)

#### Physisches Speicherlimit
* Konfigurationsschlüssel-Pfad: `container_config/memory_limit`
* Inhalt: Beschränkt den Speicher (RAM) des MySQL-Docker-Containers. `0b` deaktiviert das Speicherlimit. Aus dem tatsächlichen Speicherlimit des Containers wird die MySQL-Systemvariable `innodb_buffer_pool_size` berechnet (siehe [Verhalten von RAM-Konfigurationen](#verhalten-von-ram-konfigurationen)). Ohne Speicherlimit erhält `innodb_buffer_pool_size` 512 MiB RAM. Um diesen Wert erfolgreich anzuwenden, muss der MySQL-Container mit `cesapp recreate` neu erzeugt werden.
* Datentyp: Binäre Speicherangabe
* Valide Werte: Ganzzahl gefolgt von [b,k,m,g] (byte, kibibyte, mebibyte, gibibyte)
* Beispiel: `1750m` = 1750 MebiByte

#### Physisches Swaplimit
* Konfigurationsschlüssel-Pfad: `container_config/swap_limit`
* Inhalt: Beschränkt den Swap des MySQL-Docker-Containers. `0b` deaktiviert das Swaplimit.
* Datentyp: Binäre Speicherangabe
* Valide Werte: Ganzzahl gefolgt von [b,k,m,g] (byte, kibibyte, mebibyte, gibibyte)
* Beispiel: `1750m` = 1750 MebiByte


## Über das Verhalten von RAM- und Auslagerungsspeicher

### Verhalten von RAM-Konfigurationen

Beim Start liest das Dogu das Speicherlimit des Containers aus der cgroup (`/sys/fs/cgroup/memory.max`, bei cgroup v1 `/sys/fs/cgroup/memory/memory.limit_in_bytes`). Hat der Container kein Speicherlimit, nimmt MySQL 512 MiB für die Systemvariable `innodb_buffer_pool_size`.

Ist ein Speicherlimit gesetzt (siehe `container_config/memory_limit`), erhält `innodb_buffer_pool_size` die größte Zweierpotenz, die höchstens die Hälfte des Limits beträgt, mindestens aber 128 MiB. Die andere Hälfte bleibt frei für Verbindungen, Sortierpuffer, temporäre Tabellen und Dump-Importe. Beispiele: 600 MiB → 256 MiB, 800 MiB → 256 MiB, 1 GiB → 512 MiB, 2 GiB → 1 GiB, 4 GiB → 2 GiB, 8 GiB → 4 GiB. Weitere Informationen hierzu bietet die [MySQL-Dokumentation](https://MySQL.com/kb/en/innodb-buffer-pool/).

### Verhalten von Auslagerungsspeicher

Wenn kein Swap-Limit (siehe `container_config/swap_limit`) oder ein Null-Wert gesetzt wurde, dann wird das Swapping-Verhalten für diesen Container abgeschaltet. Wenn ein anderer Wert gesetzt wurde, dann beeinflussen mehrere Dinge das Swapping-Verhalten.

Grundsätzlich wird das angegebene Limit auf den Container zum Zeitpunkt der Container-Erzeugung angewendet. Siehe hierzu die [Docker-Dokumentation](https://docs.docker.com/config/containers/resource_constraints/#--memory-swap-details). Zudem empfiehlt die MySQL ein bestimmtes [`Swappiness`-Verhalten](https://MySQL.com/kb/en/configuring-swappiness/). Dieses Verhalten hängt jedoch überwiegend von der Swappiness-Konfiguration des Cloudogu EcoSystems ab. Die jeweilige Konfiguration lässt sich sowohl im Cloudogu EcoSystem mit `sysctl vm.swappiness` bzw. im MySQL-Container mit `docker exec -it MySQL sysctl vm.swappiness` identifizieren. Aufgrund technischer Rahmenbedingungen lässt sich derzeit jedoch nicht die Swappiness von MySQL zum Container-Startzeitpunkt automatisiert konfigurieren.