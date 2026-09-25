#!/bin/sh
# Verifies Go FIPS builds. Run inside the Go image:
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> /tests/go.sh
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp /tests/go/main.go "$work/"
cd "$work"
go mod init fipscheck >/dev/null 2>&1
go build -o fipscheck . || fail "go build failed"

info="$(go version -m fipscheck)"
echo "$info" | grep -q 'GOFIPS140=' || fail "binary not built with GOFIPS140"
pass "binary built with $(echo "$info" | grep -o 'GOFIPS140=[^ ]*')"

./fipscheck
