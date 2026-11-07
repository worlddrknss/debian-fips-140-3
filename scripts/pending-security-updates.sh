#!/usr/bin/env bash
# Prints the packages in an image that have a pending Debian security update.
#
#   scripts/pending-security-updates.sh <image>
#
# The image needs apt (the -dev variants; the distroless images are assembled
# from the same packages). Prints nothing when the image is current.
set -euo pipefail

ref="${1:?usage: pending-security-updates.sh <image>}"
docker run --rm --pull missing --user 0 --entrypoint sh "$ref" -c \
  'apt-get update -qq >/dev/null && apt-get -s upgrade 2>/dev/null' \
  | awk '/^Inst / && /-security/ {print $2}' | sort -u | paste -sd' ' -
