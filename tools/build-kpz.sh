#!/usr/bin/env bash
# Builds dist/koha-plugin-obalkyknih-<version>.kpz from Koha/.
# Usage: tools/build-kpz.sh 1.0.0 [minimum_koha_version]
set -euo pipefail

version="${1:?usage: $0 VERSION [MINIMUM_KOHA_VERSION]}"
version="${version#v}"
min_koha="${2:-24.11}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.]+)?$ ]] || { echo "bad version: $version" >&2; exit 1; }

root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -R "$root/Koha" "$stage/Koha"
pm="$stage/Koha/Plugin/Cz/ObalkyKnih.pm"
today="$(date -u +%Y-%m-%d)"
perl -pi -e "s/\{VERSION\}/$version/g; s/\{MINIMUM_VERSION\}/$min_koha/g; s/1900-01-01/$today/g" "$pm"
grep -q "{VERSION}" "$pm" && { echo "version not substituted" >&2; exit 1; }

mkdir -p "$root/dist"
out="$root/dist/koha-plugin-obalkyknih-$version.kpz"
rm -f "$out"
(cd "$stage" && find Koha -name '.DS_Store' -delete && zip -qrX "$out" Koha)
echo "$out"
