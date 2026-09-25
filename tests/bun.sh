#!/bin/sh
# Verifies the Bun image. Run inside the Bun image:
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> /tests/bun.sh
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

bun --version >/dev/null || fail "bun does not run"
bunx --version >/dev/null || fail "bunx does not run"
pass "bun $(bun --version) runs"

# `node` must be Bun's compatibility symlink, not a Node.js install.
[ "$(node -e 'console.log(typeof Bun)')" = "object" ] || fail "node is not bun"
pass "node runs Bun in Node.js compatibility mode"

# npm launchers (#!/usr/bin/env node) must work, including on distroless.
printf '#!/usr/bin/env node\nconsole.log("launcher ok")\n' > "${TMPDIR:-/tmp}/launcher"
chmod +x "${TMPDIR:-/tmp}/launcher"
[ "$("${TMPDIR:-/tmp}/launcher")" = "launcher ok" ] || fail "#!/usr/bin/env node launcher failed"
pass "#!/usr/bin/env node launchers run"

# Documents the boundary rather than enforcing anything: Bun's BoringSSL
# ignores the system FIPS configuration, so MD5 still works under bun.
if bun -e 'require("crypto").createHash("md5").update("x").digest("hex")' >/dev/null 2>&1; then
  echo "NOTE: bun computed MD5, as expected; Bun's crypto is outside the FIPS boundary"
else
  fail "bun rejected MD5; Bun's crypto behavior changed, review the README"
fi

echo "All Bun image checks passed."
