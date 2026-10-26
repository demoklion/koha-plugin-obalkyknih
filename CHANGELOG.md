# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Obálky knih API client with server-side failover (alive check, 1 h penalty
  for a dead server), URL sanitising and an optional metadata cache (off by
  default).
