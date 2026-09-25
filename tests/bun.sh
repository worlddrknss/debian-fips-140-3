#!/bin/sh
# Verifies the Bun image. Run inside the Bun image:
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> /tests/bun.sh
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

bun --version >/dev/null || fail "bun does not run"
bunx --version >/dev/null || fail "bunx does not run"
pass "bun $(bun --version) runs"

[ "$(node -p 'require("crypto").getFips()')" = "1" ] || fail "node is not in FIPS mode"
pass "node is still FIPS-enforced alongside bun"

# Documents the boundary rather than enforcing anything: Bun's BoringSSL
# ignores the system FIPS configuration, so MD5 still works under bun.
if bun -e 'require("crypto").createHash("md5").update("x").digest("hex")' >/dev/null 2>&1; then
  echo "NOTE: bun computed MD5, as expected; Bun's crypto is outside the FIPS boundary"
else
  fail "bun rejected MD5; Bun's crypto behavior changed, review the README"
fi

echo "All Bun image checks passed."
