# Contributing

Thanks for helping. Issues and pull requests are welcome in Czech, Slovak or English.

## Ground rules

- The plugin must keep the Obálky knih terms of use: no cover images stored on
  the Koha server, every cover links back to its Obálky page, the "Obálky knih"
  credit stays visible, non-commercial use only.
- No external JavaScript libraries and no build step for the browser code.
- Every UI string exists in Czech and English.
- Markup must stay accessible (alt text, keyboard focus, no layout shift).

## Development

```sh
prove -lr t/          # unit tests, no Koha needed
perl -Ilib -c lib/Koha/Plugin/Cz/ObalkyKnih.pm   # needs Koha on @INC
```

See the README for the dockerised Koha smoke test.

## Pull requests

- One topic per pull request, with a short description of why.
- Add or update tests for any change in the API client or the REST route.
- Add a line to `CHANGELOG.md` under "Unreleased".

## AI-assisted contributions

AI-assisted work is welcome if a human has reviewed it and takes responsibility
for it. Say so in the pull request description. See the README section
"How this plugin was made".

## Code of conduct

This project follows the
[Koha community code of conduct](https://koha-community.org/about/code-of-conduct/).
