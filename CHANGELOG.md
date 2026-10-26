# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-26

First public version.

### Added
- Covers from Obálky knih in OPAC search results, record detail and lists,
  and in the staff interface (search results, record detail), through Koha's
  `opac_cover_images` / `intranet_cover_images` hooks and cover slider.
- Annotation and table of contents (thumbnail and PDF link) on the record
  detail page, both optional.
- "Local cover takes priority" setting, on by default.
- Anonymous read-only REST route `/api/v1/contrib/obalkyknih/covers` that
  resolves identifiers from MARC (ISBN, ISSN, ISMN, EAN, ČNB, OCLC, volume)
  and skips suppressed and OPAC-hidden records.
- Server-side client with failover between the Obálky cache servers (alive
  check, one-hour penalty shared across Plack workers), URL sanitising and an
  optional metadata cache (off by default).
- Custom blocks via `data-obalkyknih-biblionumber` / `data-obalkyknih-isbn`
  and a small JavaScript API (`ObalkyKnih.lookup`, `ObalkyKnih.scan`).
- Configuration page in Czech and English with a connection check that shows
  the IP and referer Obálky saw.
- Mock Obálky server for development instances (`tools/mock-obalky.psgi`).
- Docs: Czech how-to, CSP and privacy notes.
