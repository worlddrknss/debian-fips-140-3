#!/usr/bin/env bash
# Scans the published images with Grype for fixable vulnerabilities.
#
#   GRYPE=anchore/grype:<version> scripts/scan-images.sh <arch>
#
# Writes table and SARIF results to scan/runtime/ and scan/dev/ (code
# scanning accepts at most 20 runs per upload) and a Markdown summary to
# $GITHUB_STEP_SUMMARY. The vulnerability database is downloaded once and
# shared by every scan, which run SCAN_JOBS (default 4) at a time. SCAN_REFS
# overrides the image list, which otherwise comes from the bake default group.
set -euo pipefail

arch="${1:?usage: scan-images.sh <arch>}"
: "${GRYPE:?set GRYPE to the Grype image}"
jobs="${SCAN_JOBS:-4}"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
db="$PWD/scan/.grype-db"
mkdir -p scan/runtime scan/dev "$db"

docker run --rm -v "$db:/db" -e GRYPE_DB_CACHE_DIR=/db "$GRYPE" db update

scan_one() {
  local ref="$1" name dir
  name="${ref//:/_}"
  case "$ref" in
    *-dev) dir=scan/dev ;;
    *) dir=scan/runtime ;;
  esac
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$db:/db" -e GRYPE_DB_CACHE_DIR=/db -e GRYPE_DB_AUTO_UPDATE=false \
    -v "$PWD/$dir:/scan" \
    "$GRYPE" "$ref" --only-fixed --quiet \
    -o "table=/scan/$name.txt" -o "sarif=/scan/$name.sarif"
  # A distinct category per image and arch keeps code scanning from treating
  # the uploads as one run.
  jq --arg id "grype/$name/$arch/" '.runs[].automationDetails = {id: $id}' \
    "$dir/$name.sarif" > "$dir/$name.tmp"
  mv "$dir/$name.tmp" "$dir/$name.sarif"
}
export -f scan_one
export GRYPE db arch

refs="${SCAN_REFS:-$(docker buildx bake --print 2>/dev/null | jq -r '.target[].tags[0]' | sort)}"
# $1 is expanded by the child shell xargs starts, hence the single quotes.
# shellcheck disable=SC2016
echo "$refs" | xargs -P "$jobs" -I{} bash -c 'scan_one "$1"' _ {}

# Summary in a stable order once all scans are done.
shopt -s nullglob
for table in scan/runtime/*.txt scan/dev/*.txt; do
  ref="$(basename "$table" .txt | sed 's/_/:/')"
  {
    echo "### $ref ($arch)"
    echo '```'
    cat "$table"
    echo '```'
  } >> "$summary"
done
