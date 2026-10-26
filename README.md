# Obálky knih for Koha

A [Koha](https://koha-community.org/) plugin that shows book covers,
annotations and tables of contents from
[Obálky knih](https://www.obalkyknih.cz/) (obalkyknih.cz), the cover service
used by most Czech libraries.

**Česky:** [návod k instalaci a nastavení](docs/navod.md).

- Covers in OPAC search results, record detail and lists, and in the staff
  interface (search results and record detail).
- Annotation and table of contents (thumbnail linking to the PDF) on the
  record detail page, both optional.
- Your own Koha local covers take priority (switchable).
- Server-side failover between the Obálky cache servers, as the Obálky
  manual requires.
- Czech and English, accessible markup, no external JavaScript libraries,
  works with Koha's Content Security Policy.
- Keeps the Obálky terms: images are never stored on your server, every
  cover links back to its Obálky page and carries the "Obálky knih" credit.

Requires Koha 24.11 or newer (tested in CI on 24.11 and 26.05).

## Install

1. Plugins must be enabled in `koha-conf.xml` (`<enable_plugins>1</enable_plugins>`,
   then restart Plack). See the
   [Koha manual](https://koha-community.org/manual/latest/en/html/plugins.html).
2. Download the `.kpz` from the
   [latest release](https://github.com/demoklion/koha-plugin-obalkyknih/releases/latest).
3. Staff interface → *Administration → Manage plugins → Upload plugin*.
4. Restart Plack once (`koha-plack --restart <instance>`) so the REST routes
   load.

## Register at Obálky knih

Obálky serves only registered catalogues. Registration is free and for
non-commercial library use. In your account at
<https://www.obalkyknih.cz/account>, add:

| What | Field | Example |
|---|---|---|
| Every URL your OPAC is reachable at | *URL adresa katalogu* | `https://katalog.example.cz` |
| The staff interface URL, if it differs (port counts) | *URL adresa katalogu* | `https://katalog.example.cz:8443` |
| The public IP of the Koha server | *IP adresa systému* | `192.0.2.10` |

The catalogue URL lets readers' browsers load images (Obálky checks the
`Referer`). The IP lets the Koha server ask for metadata. New entries may take
effect only after the Obálky team approves the account.

Not sure which IP the Koha server uses? Open the plugin configuration and
press **Check connection**: if Obálky refuses, the page shows the IP and
referer Obálky saw.

## Configure

*Administration → Manage plugins → Obálky knih → Actions → Configure*

| Setting | Default | Notes |
|---|---|---|
| Online catalogue / Staff interface | on / on | |
| Local cover takes priority | on | A cover uploaded in Koha wins over Obálky. |
| Cover size (results, detail) | medium / medium | small 54×68, medium 170×240, large 510×720 |
| Show annotation / table of contents | on / on | Record detail page |
| Obálky knih servers | cache, cache2, cache3 | In failover order |
| Library sigla | empty | Optional; only tags promotional blocks for Obálky statistics |
| Metadata cache | 0 (off) | See "Caching" below |
| Request timeout | 6 s | |
| Test mode | off | Allows a mock server on a development instance |

### Content Security Policy and privacy

If you send a CSP header, add `img-src https://*.obalkyknih.cz`, and do not set
`Referrer-Policy: no-referrer`. Details in [docs/csp.md](docs/csp.md).

Readers' browsers contact obalkyknih.cz. Text for your privacy page, in Czech
and English: [docs/privacy.md](docs/privacy.md).

## Covers anywhere: custom blocks

Any element with `data-obalkyknih-biblionumber` (or `data-obalkyknih-isbn`)
gets a cover, for example in a "New in the library" block in `OpacMainUserBlock`:

```html
<a href="/cgi-bin/koha/opac-detail.pl?biblionumber=42">
  <span data-obalkyknih-biblionumber="42" data-obalkyknih-size="medium"
        data-obalkyknih-title="Babička">
    <!-- fallback shown when Obálky has no cover, e.g. a local cover -->
    <img src="/cgi-bin/koha/opac-image.pl?biblionumber=42" alt="Babička">
  </span>
</a>
```

The content is replaced only when Obálky has a cover that actually loads. Add
`data-obalkyknih-local` to keep the fallback when "local cover takes priority"
is on. The element gets `data-obalkyknih-state="cover"` or `"none"` and fires an
`obalkyknih:cover` event. Content added later can be processed with
`ObalkyKnih.scan(element)`.

JavaScript API on every OPAC and staff page:

```js
ObalkyKnih.lookup({ biblionumbers: [42, 43], isbns: ["9788074151330"] })
  .then(items => { /* { b42: {...}, i9788074151330: {...} } */ });
ObalkyKnih.coverUrl(item, "medium", "keywords");
```

REST route (anonymous, read-only, at most 50 identifiers per call):

```
GET /api/v1/contrib/obalkyknih/covers?biblionumber=42&biblionumber=43&isbn=9788074151330
```

Each item carries only `cover_*_url`, `toc_thumbnail_url`, `toc_pdf_url`,
`backlink_url`, `orig_width`, `orig_height` and `annotation {text, source}`.
Records with no cover are left out. Suppressed and OPAC-hidden records get
nothing.

## How it works

- The browser sends biblionumbers to the plugin route. The Koha server reads
  the identifiers from MARC (020 ISBN, 022 ISSN, 024 ISMN/EAN, 015 ČNB,
  035 OCLC, 245 $n $p for volumes) and calls
  `/api/books?multi=…` on the first healthy Obálky server.
- Failover: a server that errors, returns broken JSON or times out (while
  `/api/runtime/alive` also fails) is skipped for one hour. The state is shared
  across Plack workers through the Koha cache. A healthy but slow server
  (the first lookup of an uncached record can take long) is not penalised.
- Only `https://*.obalkyknih.cz` URLs survive. Image hosts follow the server
  that answered, so a failover also moves images. Text is inserted as text,
  never as HTML.
- Koha's own cover slider (`verify_cover_images`) is held back for up to
  3 seconds until the Obálky images are in, so they join the normal slider.
  The backlink is added after Koha's lightbox setup, so a click opens the
  Obálky page as the terms require.

### Caching

The Obálky terms forbid storing cover images on the library's server. The
plugin never does: images always load in the reader's browser straight from
obalkyknih.cz. Short caching of the metadata JSON is common (VuFind caches for
30 minutes), but it is not yet confirmed for this plugin, so the metadata
cache is off by default. Only the health state of the servers is cached.

## Development

```sh
prove -lr t/                    # unit tests, no Koha needed
tools/build-kpz.sh 1.2.3        # dist/koha-plugin-obalkyknih-1.2.3.kpz
plackup -p 8591 tools/mock-obalky.psgi   # mock Obálky server for dev instances
```

CI runs the unit tests, then installs the plugin into
[koha-testing-docker](https://gitlab.com/koha-community/koha-testing-docker)
on Koha 24.11 and 26.05 and smoke-tests the routes and the OPAC page. A tag
`vX.Y.Z` builds the `.kpz` and publishes a release.

Mock server: tick *Test mode* in the configuration and set the server to
`http://<host>:8591`. Identifiers ending in an even digit get a generated
cover, odd ones none.

Not yet verified against the live service (waiting for registration),
see the issues:

- whether Obálky accepts several ISBNs per work as an array (the plugin sends
  one);
- whether the image hosts in the JSON follow the answering cache server.

## How this plugin was made

This plugin was written with AI. [Claude](https://www.anthropic.com/claude)
(Anthropic's model, used through Claude Code) researched the Obálky manual,
the cbvk/obalkyknih source, VuFind's and Knihovny.cz's implementations and the
Koha source, then wrote the code, tests and documentation.
[Ján Dugovič](https://jandu.top/) directed the work, made the product and
design decisions, and maintains it. Every
AI-written commit carries a `Co-Authored-By: Claude` trailer, so the history
shows what was written this way.

If you find a mistake, please open an issue; a human will answer.

## Licence

GPL-3.0-or-later, the same as Koha. See [LICENSE](LICENSE).

Not affiliated with Obálky knih, Moravská zemská knihovna or Jihočeská vědecká
knihovna. "Obálky knih" is the name of their service.
