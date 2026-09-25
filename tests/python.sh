#!/bin/sh
# Verifies Python's ssl and hashlib go through the OpenSSL FIPS provider. Run
# inside the Python image:
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> /tests/python.sh
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

system_openssl="$(openssl version | awk '{print $2}')"
py_openssl="$(python3 -c 'import ssl; print(ssl.OPENSSL_VERSION.split()[1])')"
[ "$py_openssl" = "$system_openssl" ] || fail "Python uses OpenSSL $py_openssl, system has $system_openssl"
pass "Python $(python3 -c 'import sys; print(sys.version.split()[0])') uses the system OpenSSL $py_openssl"

python3 - <<'PY' || fail "hashlib/hmac enforcement"
import hashlib, hmac, io, sys

def rejected(label, fn):
    try:
        fn()
    except ValueError:
        print(f"PASS: {label} is rejected")
        return
    sys.exit(f"FAIL: {label} succeeded")

def openssl(label, obj):
    kind = f"{type(obj).__module__}.{type(obj).__name__}"
    if kind != "_hashlib.HASH":
        sys.exit(f"FAIL: {label} used {kind}, not OpenSSL")
    print(f"PASS: {label} runs in OpenSSL")

openssl("hashlib.sha256()", hashlib.sha256(b"x"))
openssl('hashlib.new("sha384")', hashlib.new("sha384", b"x"))
openssl("hashlib.sha3_256()", hashlib.sha3_256(b"x"))
rejected("hashlib.md5()", lambda: hashlib.md5(b"x"))
rejected('hashlib.new("md5")', lambda: hashlib.new("md5", b"x"))
rejected("hashlib.blake2b()", lambda: hashlib.blake2b(b"x"))
rejected("hmac with md5", lambda: hmac.new(b"k", b"m", "md5"))
rejected("hashlib.file_digest with md5", lambda: hashlib.file_digest(io.BytesIO(b"x"), "md5"))

# FIPS permits non-approved algorithms for non-security uses.
hashlib.md5(b"x", usedforsecurity=False).hexdigest()
print("PASS: hashlib.md5(usedforsecurity=False) works for non-security use")
PY

tmp="$(mktemp -d)"
server_pids=""
trap 'kill $server_pids 2>/dev/null; rm -rf "$tmp"' EXIT
openssl req -x509 -newkey EC -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
  -subj /CN=localhost -keyout "$tmp/tls.key" -out "$tmp/tls.crt" 2>/dev/null
openssl s_server -quiet -accept 127.0.0.1:8443 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  >/dev/null 2>&1 &
server_pids="$server_pids $!"
openssl s_server -quiet -accept 127.0.0.1:8444 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  -ciphersuites TLS_AES_128_GCM_SHA256 -cipher ECDHE-ECDSA-AES128-GCM-SHA256 >/dev/null 2>&1 &
server_pids="$server_pids $!"
sleep 1

tls_client='
import socket, ssl, sys
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
with socket.create_connection(("127.0.0.1", int(sys.argv[1]))) as sock:
    with ctx.wrap_socket(sock) as tls:
        print(tls.cipher()[0])
'
cipher="$(python3 -c "$tls_client" 8443)" || fail "Python TLS handshake failed"
[ "$cipher" = "TLS_AES_256_GCM_SHA384" ] || fail "Python negotiated $cipher"
pass "Python ssl negotiates AES-256 by default"
python3 -c "$tls_client" 8444 >/dev/null 2>&1 && fail "Python accepted an AES-128-only server"
pass "Python ssl refuses AES-128-only servers"

# Wheels that bundle their own OpenSSL 3 (pyca/cryptography) load the base
# image's FIPS provider through OPENSSL_MODULES and OPENSSL_CONF. Needs pip and
# network access, so it runs on the dev variant only.
if python3 -m pip --version >/dev/null 2>&1; then
  python3 -m venv "$tmp/venv"
  "$tmp/venv/bin/pip" install --quiet --disable-pip-version-check cryptography==46.0.3 \
    || fail "installing cryptography"
  "$tmp/venv/bin/python" - <<'PY' || fail "cryptography FIPS checks"
import sys
from cryptography.hazmat.bindings._rust import openssl
from cryptography.hazmat.primitives import hashes

if not openssl.is_fips_enabled():
    sys.exit("FAIL: cryptography's bundled OpenSSL is not in FIPS mode")
try:
    digest = hashes.Hash(hashes.MD5())
    digest.update(b"x")
    digest.finalize()
except Exception:
    pass
else:
    sys.exit("FAIL: cryptography computed MD5")
print(f"PASS: cryptography wheel ({openssl.openssl_version_text()}) runs in FIPS mode and rejects MD5")
PY
fi

echo "All Python FIPS checks passed."
