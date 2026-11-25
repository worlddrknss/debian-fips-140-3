#!/usr/bin/env bash
# Prints the fixable HIGH/CRITICAL vulnerabilities Trivy finds in an image,
# one "ID package installed->fixed" per line; prints nothing when it is clean.
#
#   scripts/trivy-fixable.sh <image>
#
# This is the same scan the downstream apps (Vara Performance, D76 Riders,
# madebymeyrill) run as a release gate on every image built from these bases
# (their scripts/trivy-gate.mjs): Trivy, vulnerability scanner only, HIGH and
# CRITICAL, --ignore-unfixed. A finding here blocks their releases, so the
# daily security-updates check rebuilds on it too, not only on what apt sees
# in the Debian security archive.
set -euo pipefail

ref="${1:?usage: trivy-fixable.sh <image>}"
# Pinned by digest (0.76.1), the same as the apps' gate: Trivy's own release
# tags have been hijacked before.
TRIVY="${TRIVY:-aquasec/trivy@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c}"
cache="${TRIVY_CACHE:-$PWD/.trivy-cache}"
mkdir -p "$cache"

docker run --rm -v "$cache:/root/.cache" -v /var/run/docker.sock:/var/run/docker.sock \
  "$TRIVY" image --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed \
  --format json "$ref" \
  | jq -r '.Results[]?.Vulnerabilities[]? | "\(.VulnerabilityID) \(.PkgName) \(.InstalledVersion)->\(.FixedVersion)"' \
  | sort -u
