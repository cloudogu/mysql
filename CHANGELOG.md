# MySQL Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Changed
- Upgrade mysql to 8.4.2 (LTS)

## [v8.0.38-3] - 2024-09-18
### Changed
- Relicense to AGPL-3.0-only

## [v8.0.38-2] - 2024-08-07
### Changed
- Upgrade debian base image to 12.6-1

### Security
- fix CVE-2024-41110 (#22)

## [v8.0.38-1] - 2024-07-02
### Changed
- Upgrade mysql to 8.0.38
- Upgrade debian base image to 12.5-4
- Upgrade makefiles to 9.1.0

### Fixed
- Fixed a bug, where it was not possible to do a dogu upgrade, when no service accounts existed
- Fixed the upgrade-scripts which previously produced an error

## [v8.0.33-4] - 2024-06-10
### Changed
- [#19] Move state that should be persistent between restarts to local config.

## [v8.0.33-3] - 2024-04-09
### Fixed
- Fixed CVE-2023-25775 CVE-2023-5178

### Changed
- Upgrade Makefiles to 9.0.3

## [v8.0.33-2] - 2023-06-27
### Added
- Config options for [resource requirements](https://github.com/cloudogu/dogu-development-docs/blob/main/docs/important/relevant_functionalities_en.md#resource-requirements) (#14)

## [v8.0.33-1] - 2023-04-24
### Changed
- Update Base-image to 11.6-1 (#12)
- Update Mysql to Version 8.0.33 (#12)
  
## [v8.0.32-1] - 2023-02-13
### Changed
- Upgrade mysql to Version 8.0.32 (#10)
- Do not use flag `--log-warnings` anymore as it has been removed in mysql8
  - Use `log_error_verbosity` instead and set default log level to WARN.

## [v5.7.37-4] - 2022-06-16
### Changed
- Remove mysql lockfile (/var/run/mysqld/mysqld.sock) at dogu startup (#8)

## [v5.7.37-3] - 2022-05-18
### Changed
- docker container user is now root (#6)
- mysqld process runs under 'mysql' user (#6)

## [v5.7.37-2] - 2022-04-11
### Changed
- Upgrade packages to fix CVE-2018-25032; #4

## [v5.7.37-1] - 2022-03-15
### Added
- Add MySQL v5.7.37 (#1)
