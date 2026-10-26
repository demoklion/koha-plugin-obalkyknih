# Security policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems.

Report privately through GitHub: **Security → Report a vulnerability** on
https://github.com/demoklion/koha-plugin-obalkyknih/security/advisories/new

You can write in Czech, Slovak or English. Expect a first reply within 7 days.
Please include the plugin version, the Koha version and steps to reproduce.

## Supported versions

Only the latest release gets security fixes.

## Scope

In scope: the plugin's Perl code, its REST route, its OPAC and staff JavaScript
and its configuration page.

Out of scope: Koha itself (report to the Koha security team, see
https://koha-community.org/security/) and the Obálky knih service
(contact the service operator at https://www.obalkyknih.cz/).

## Design notes relevant to security

- The plugin stores no cover images on the Koha server; readers' browsers load
  them from `*.obalkyknih.cz`.
- The REST route is read-only, accepts only normalised identifiers
  (ISBN, ISSN, ČNB, OCLC, EAN) and caps the batch size.
- Everything taken from Obálky responses is treated as untrusted: URLs must be
  `https://` on an `obalkyknih.cz` host, and text is inserted as text, never
  as HTML.
