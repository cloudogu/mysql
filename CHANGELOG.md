# Mariadb Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Changed
- Upgrade mysql to Version 8.0.32 (#10)

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
