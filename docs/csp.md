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
match the catalogue URL you registered. The plugin's images and
table-of-contents links carry `referrerpolicy="origin"`: Obálky gets only the
catalogue origin (e.g. `https://katalog.example.cz/`), never the page path.
This works even on pages that send `Referrer-Policy: no-referrer`, because the
element attribute takes precedence.

If you build cover images yourself with `ObalkyKnih.coverUrl()`, set
`referrerpolicy="origin"` on them too.

## Česky

- Do `img-src` přidejte `https://*.obalkyknih.cz`.
- Obrázky pluginu posílají Obálkám jen adresu katalogu (`referrerpolicy="origin"`),
  takže fungují i na stránkách s `Referrer-Policy: no-referrer`.
