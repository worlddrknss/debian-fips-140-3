#!/bin/sh
# Writes release notes and SBOM files for one published build.
#
#   release-notes.sh <subjects.json> <out-dir>
#
# subjects.json is the manifest job's list of published images:
#   [{"name": "ghcr.io/o/debian-fips-base", "tag": "latest", "digest": "sha256:..."}, ...]
# Writes <out-dir>/notes.md and one SPDX JSON file per image (linux/amd64),
# read from the SBOM attestations BuildKit attached at build time.
set -eu

subjects="$1"
out="$2"
mkdir -p "$out/sbom"
notes="$out/notes.md"

{
  echo "Images built from commit ${GITHUB_SHA:-unknown} (build tag \`${BUILD_TAG:-unknown}\`)."
  echo
  echo "| Image | Tag | FIPS module | Packages | Digest |"
  echo "| --- | --- | --- | --- | --- |"
} > "$notes"

jq -c '.[]' "$subjects" | while read -r subject; do
  name="$(echo "$subject" | jq -r .name)"
  tag="$(echo "$subject" | jq -r .tag)"
  digest="$(echo "$subject" | jq -r .digest)"
  image="${name##*/}"
  ref="$name@$digest"

  labels="$(docker buildx imagetools inspect "$ref" \
    --format '{{ json (index .Image "linux/amd64").Config.Labels }}')"
  module="$(echo "$labels" | jq -r '
    if ."fips.bun.crypto" == "not-validated" then "none for Bun (BoringSSL); base: OpenSSL FIPS provider \(."fips.openssl.provider.version")"
    elif ."fips.java.module" then "\(."fips.java.module") (CMVP #\(."fips.java.module.cmvp"))"
    elif ."fips.go.module.version" then "Go Cryptographic Module \(."fips.go.module.version") (CMVP #\(."fips.go.module.cmvp"))"
    elif ."fips.openssl.provider.cmvp" == "in-process" then "OpenSSL FIPS provider \(."fips.openssl.provider.version") (in CMVP review, not validated)"
    else "OpenSSL FIPS provider \(."fips.openssl.provider.version") (CMVP #\(."fips.openssl.provider.cmvp"))" end')"

  sbom="$out/sbom/$image-$tag.spdx.json"
  docker buildx imagetools inspect "$ref" \
    --format '{{ json (index .SBOM "linux/amd64").SPDX }}' > "$sbom"
  packages="$(jq '[.packages[]? | select(.name != null)] | length' "$sbom")"

  echo "| \`$image\` | \`$tag\` | $module | $packages | \`$digest\` |" >> "$notes"
done

cat >> "$notes" <<'MD'

The attached `*.spdx.json` files are the SPDX SBOMs for linux/amd64, as
attached to each image at build time. Every image also carries SLSA
provenance and a GitHub build attestation:

```sh
gh attestation verify oci://ghcr.io/<owner>/<image>@<digest> --owner <owner>
```
MD
