#!/bin/sh
# Verifies Node.js runs its crypto through the OpenSSL FIPS provider. Run inside the Node image:
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> /tests/node.sh
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

if OPENSSL_MODULES=/nonexistent node -e '' 2>/dev/null; then
  fail "Node started without the FIPS provider"
fi
pass "Node refuses to start when the FIPS provider can't be loaded"

[ "$(node -p 'require("crypto").getFips()')" = "1" ] || fail "crypto.getFips() is not 1"
pass "crypto.getFips() is 1 (Node's bundled OpenSSL $(node -p 'process.versions.openssl'))"

node -e 'require("crypto").createHash("sha256").update("x").digest()' \
  || fail "SHA-256 unavailable"
pass "approved algorithm SHA-256 works"

node -e 'require("crypto").createHash("md5")' 2>/dev/null && fail "MD5 succeeded"
pass "non-approved algorithm MD5 is rejected"

node -e 'require("crypto").createCipheriv("chacha20-poly1305", Buffer.alloc(32), Buffer.alloc(12), { authTagLength: 16 })' \
  2>/dev/null && fail "ChaCha20-Poly1305 succeeded"
pass "non-approved cipher ChaCha20-Poly1305 is rejected"

node -e '
const { generateKeyPairSync, sign, verify } = require("crypto");
const { privateKey, publicKey } = generateKeyPairSync("ml-dsa-65");
const sig = sign(null, Buffer.from("x"), privateKey);
if (!verify(null, Buffer.from("x"), publicKey, sig)) process.exit(1);
' || fail "ML-DSA-65 sign/verify failed"
pass "ML-DSA-65 sign/verify works"

tmp="$(mktemp -d)"
trap 'kill $server_pid 2>/dev/null; rm -rf "$tmp"' EXIT
openssl req -x509 -newkey EC -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
  -subj /CN=localhost -keyout "$tmp/tls.key" -out "$tmp/tls.crt" 2>/dev/null
openssl s_server -quiet -accept 127.0.0.1:8443 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  -tls1_3 -groups X25519MLKEM768 >/dev/null 2>&1 &
server_pid=$!
sleep 1
tls_client='
const tls = require("tls");
const port = Number(process.argv[1]);
const s = tls.connect({ host: "127.0.0.1", port, rejectUnauthorized: false }, () => {
  console.log(s.getCipher().standardName, s.getEphemeralKeyInfo().name);
  s.end();
});
s.on("error", e => { console.error(e.message); process.exit(1); });
'

result="$(node -e "$tls_client" 8443)" || fail "Node TLS 1.3 handshake failed"
[ "${result#* }" = "X25519MLKEM768" ] || fail "Node negotiated group ${result#* }"
pass "Node negotiates hybrid PQC TLS (X25519MLKEM768)"
[ "${result% *}" = "TLS_AES_256_GCM_SHA384" ] || fail "Node negotiated ${result% *}"
pass "Node negotiates AES-256 by default"

# A server that only offers AES-128 must be refused (CJIS 256-bit minimum).
openssl s_server -quiet -accept 127.0.0.1:8444 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  -ciphersuites TLS_AES_128_GCM_SHA256 \
  -cipher ECDHE-ECDSA-AES128-GCM-SHA256 >/dev/null 2>&1 &
server_pid="$server_pid $!"
sleep 1
node -e "$tls_client" 8444 >/dev/null 2>&1 && fail "Node accepted an AES-128-only server"
pass "Node refuses AES-128-only servers"

echo "All Node.js FIPS checks passed."
