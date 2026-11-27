# Configuration of the MySQL Dogu

## Prerequisite

* MySQL is successfully [installed](Install_Dogu_en.md)

## Configuration options

The MySQL-Dogu is configured via the registry.
There are several ways to configure values in the registry.
In short you can:
1. configure a dogu with `kubectl edit configmap mysql-config` (recommended)
2. update the configuration values using a blueprint

## Configuration

All configuration keys for MySQL settings have the key prefix `/config/mysql/`.
MySQL provides the following settings:

#### logging behavior
* Configuration key path: `logging/root`
* Content: Modifies the logging behavior of the MySQL Docker container. This value becomes active only after container restart.
* Data type: String
* Valid values: ERROR, WARN, INFO, DEBUG
* Default value: ERROR
* See [logging_en.md](logging_en.md)

#### Physical memory limit
* Configuration key path: `container_config/memory_limit`
* Content: Limits the memory (RAM) of the MySQL Docker container. `0b` disables the memory limit. The MySQL system variable `innodb_buffer_pool_size` is calculated from the actual memory limit of the container (see [Behavior of RAM configurations](#behavior-of-ram-configurations)). Without a memory limit, `innodb_buffer_pool_size` receives 512 MiB of RAM. To successfully apply this value, the MySQL container must be re-created using `cesapp recreate`. 
* Data type: Binary memory specification.
* Valid values: Integer followed by [b,k,m,g] (byte, kibibyte, mebibyte, gibibyte)
* Example: `1750m` = 1750 MebiByte

#### Physical swap limit
* Configuration key path: `container_config/swap_limit`
* Content: Limits the swap of the MySQL Docker container. `0b` will disable swapping.
* Data type: Binary storage specification.
* Valid values: Integer followed by [b,k,m,g] (byte, kibibyte, mebibyte, gibibyte)
* Example: `1750m` = 1750 MebiByte


## About RAM and swap memory behavior

### Behavior of RAM configurations

On startup, the dogu reads the memory limit of the container from the cgroup (`/sys/fs/cgroup/memory.max`, or `/sys/fs/cgroup/memory/memory.limit_in_bytes` with cgroup v1). If the container has no memory limit, MySQL takes 512 MiB for the `innodb_buffer_pool_size` system variable.

If a memory limit is set (see `container_config/memory_limit`), `innodb_buffer_pool_size` gets the largest power of two that is at most half of the limit, but at least 128 MiB. The other half stays free for connections, sort buffers, temporary tables and dump imports. Examples: 600 MiB → 256 MiB, 800 MiB → 256 MiB, 1 GiB → 512 MiB, 2 GiB → 1 GiB, 4 GiB → 2 GiB, 8 GiB → 4 GiB. See the [MySQL documentation](https://MySQL.com/kb/en/innodb-buffer-pool/) for more information.

### Behavior of Swap memory configurations

If no swap limit (see `container_config/swap_limit`) or a zero value has been set, then swapping behavior is disabled for this container. If a different value was set, then several things affect the swapping behavior.

Basically, the specified limit is applied to the container at container creation time. See the [Docker documentation](https://docs.docker.com/config/containers/resource_constraints/#--memory-swap-details) for more information. In addition, MySQL recommends a certain [`swappiness` behavior](https://MySQL.com/kb/en/configuring-swappiness/). However, this behavior depends predominantly on the swappiness configuration of the Cloudogu EcoSystem. The respective configuration can be identified both in the Cloudogu EcoSystem with `sysctl vm.swappiness` or in the MySQL container with `docker exec -it MySQL sysctl vm.swappiness`. However, due to technical constraints, it is currently not possible to automatically configure the swappiness of MySQL at container startup time.
