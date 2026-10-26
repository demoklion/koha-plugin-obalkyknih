# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Docs: installing from Koha's own plugin search (`plugin_repos` in
  `koha-conf.xml`), in the README and the Czech guide.

## [0.1.3] - 2026-10-26

### Added
- Image fallback in the browser: when one Obálky cache server refuses a cover
  or table-of-contents image (a registration not yet active on that server,
  or the server is down), the same file is tried on the other configured
  servers before the cover is given up.

## [0.1.2] - 2026-10-26

### Fixed
- The OPAC and staff script and stylesheet did not load: Koha rejected the
  `?v=` cache-busting parameter (400 "Malformed query string") because the
  static routes did not declare it. CI now requests the exact asset URLs from
  the rendered OPAC page.
- Release checksum file names the `.kpz` without the build machine's path, so
  `sha256sum -c` works after download.
- Record detail: annotation and table of contents go into the record column
  instead of the narrow cover column.

## [0.1.1] - 2026-10-26

### Added
- Test mode accepts root-relative image paths, and the mock server takes
  `MOCK_PREFIX`, so a mock proxied under the catalogue's own origin works on
  any development hostname.
- Test that drives the client against the mock server.

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
