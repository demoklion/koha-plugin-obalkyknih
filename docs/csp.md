# Content Security Policy and Referrer-Policy

## img-src

Covers and table-of-contents thumbnails load in the reader's browser from the
Obálky cache servers. If your OPAC or staff interface sends a
`Content-Security-Policy` header, allow them:

```
img-src 'self' data: https://*.obalkyknih.cz;
```

Koha 24.11+ has the `OpacContentSecurityPolicy` / `IntranetContentSecurityPolicy`
system preferences (or set the header in Apache). The table-of-contents PDF opens as a
normal link, so it needs no CSP entry.

`connect-src 'self'` is enough: the browser talks only to your own Koha
(`/api/v1/contrib/obalkyknih/...`), never to the Obálky API.

## Referrer-Policy

Obálky decides whether to serve an image by the `Referer` header, which must
match the catalogue URL you registered. Browsers send the origin by default
(`strict-origin-when-cross-origin`), which is what Obálky matches on.

Do **not** set `Referrer-Policy: no-referrer` (or `same-origin`) on OPAC
pages, or every cover will fail with a 404. The plugin itself never adds
`referrerpolicy="no-referrer"` to its images.

## Česky

- Do `img-src` přidejte `https://*.obalkyknih.cz`.
- Nenastavujte `Referrer-Policy: no-referrer` ani `same-origin`; Obálky podle
  hlavičky Referer poznají registrovaný katalog.
