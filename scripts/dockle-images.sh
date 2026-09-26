#!/usr/bin/env bash
# Checks the built images against the CIS Docker Benchmark with Dockle.
#
#   DOCKLE=goodwithtech/dockle:<version> scripts/dockle-images.sh
#
# Runtime (distroless) images fail on any WARN or FATAL finding. -dev images
# are build environments that run as root and keep tools such as su and
# passwd, so their findings are reported only. Ignored everywhere:
#   CIS-DI-0005  Docker Content Trust: superseded by the cosign signatures
#                and provenance attestations the publish job adds.
#   CIS-DI-0006  HEALTHCHECK: a base image can't know how its app is checked;
#                orchestrators define their own probes.
# SCAN_REFS overrides the image list, which otherwise comes from the bake
# default group.
set -euo pipefail

: "${DOCKLE:?set DOCKLE to the Dockle image}"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
refs="${SCAN_REFS:-$(docker buildx bake --print 2>/dev/null | jq -r '.target[].tags[0]' | sort)}"
status=0

echo "### CIS Docker Benchmark (Dockle)" >> "$summary"
for ref in $refs; do
  case "$ref" in
    *-dev) level=fatal ;;  # report only; nothing in dev images is FATAL
    *) level=warn ;;
  esac
  if out="$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$DOCKLE" \
      --no-color --exit-code 1 --exit-level "$level" \
      --ignore CIS-DI-0005 --ignore CIS-DI-0006 "$ref" 2>&1)"; then
    result=pass
  else
    result=FAIL
    status=1
  fi
  {
    echo "<details><summary>$ref: $result</summary>"
    echo
    echo '```'
    echo "$out"
    echo '```'
    echo "</details>"
  } >> "$summary"
  echo "$ref: $result"
done
exit "$status"
