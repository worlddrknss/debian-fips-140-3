#!/bin/sh
# Verifies that the image enforces the FIPS provider. Run inside the image:
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> /tests/base.sh
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

providers="$(openssl list -providers)"
echo "$providers" | grep -q 'OpenSSL FIPS Provider' || fail "FIPS provider not loaded"
echo "$providers" | grep -A3 "^  fips" | grep -q 'status: active' || fail "FIPS provider not active"
echo "$providers" | grep -q '^  default' && fail "default provider is loaded"
pass "only fips and base providers are active"

modules_dir="$(openssl version -m | sed -E 's/^MODULESDIR: "(.*)"$/\1/')"
[ -e "$modules_dir/legacy.so" ] && fail "legacy provider module is installed"
openssl list -provider legacy -cipher-algorithms >/dev/null 2>&1 \
  && fail "legacy provider can be loaded"
pass "legacy provider is not installed"

echo test | openssl dgst -sha256 >/dev/null || fail "SHA-256 unavailable"
pass "approved algorithm SHA-256 works"

echo test | openssl dgst -md5 >/dev/null 2>&1 && fail "MD5 succeeded"
pass "non-approved algorithm MD5 is rejected"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:1024 >/dev/null 2>&1 \
  && fail "RSA-1024 key generation succeeded"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 >/dev/null 2>&1 \
  || fail "RSA-3072 key generation failed"
pass "RSA key size limits are enforced"

tmp="$(mktemp -d)"
server_pids=""
trap 'kill $server_pids 2>/dev/null; rm -rf "$tmp"' EXIT

openssl req -x509 -newkey EC -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
  -subj /CN=localhost -keyout "$tmp/tls.key" -out "$tmp/tls.crt" 2>/dev/null \
  || fail "TLS test certificate generation failed"

# The server allows every protocol version it can, so any refusal of
# TLS 1.0/1.1 comes from the FIPS configuration, not from the server.
openssl s_server -quiet -accept 127.0.0.1:8442 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  >/dev/null 2>&1 &
server_pids="$server_pids $!"
sleep 1
for v in tls1 tls1_1; do
  echo Q | openssl s_client -connect 127.0.0.1:8442 -"$v" -brief >/dev/null 2>&1 \
    && fail "$v handshake succeeded"
done
echo Q | openssl s_client -connect 127.0.0.1:8442 -tls1_2 -brief >/dev/null 2>&1 \
  || fail "TLS 1.2 handshake failed"
pass "TLS 1.0/1.1 are refused, TLS 1.2 works"

# CJIS requires 256-bit symmetric keys. The server uses the system policy;
# clients that offer only AES-128 must be refused.
if echo Q | openssl s_client -connect 127.0.0.1:8442 -tls1_3 \
  -ciphersuites TLS_AES_128_GCM_SHA256 -brief >/dev/null 2>&1; then
  fail "TLS 1.3 negotiated AES-128"
fi
if echo Q | openssl s_client -connect 127.0.0.1:8442 -tls1_2 \
  -cipher ECDHE-ECDSA-AES128-GCM-SHA256 -brief >/dev/null 2>&1; then
  fail "TLS 1.2 negotiated AES-128"
fi
negotiated="$(echo Q | openssl s_client -connect 127.0.0.1:8442 -brief 2>&1 \
  | sed -n 's/^Ciphersuite: //p')"
[ "$negotiated" = "TLS_AES_256_GCM_SHA384" ] || fail "default TLS negotiated '$negotiated'"
pass "TLS allows only AES-256-GCM (CJIS 256-bit minimum)"

# Distroless images record packages in status.d. Each one must keep its
# copyright file, which redistributing its binaries requires.
if [ -d /var/lib/dpkg/status.d ]; then
  for record in /var/lib/dpkg/status.d/*; do
    case "$record" in *.md5sums) continue ;; esac
    pkg="${record##*/}"
    [ -f "/usr/share/doc/$pkg/copyright" ] || fail "no copyright file for package $pkg"
  done
  pass "every installed package ships its copyright file"

  # NIST SP 800-190 / 800-53 CM-7: distroless images carry no privilege
  # escalation paths and nothing a non-root process could tamper with.
  # find exits non-zero on directories the test user cannot read; its output
  # is what matters.
  privileged="$(find / -xdev -type f -perm /6000 2>/dev/null || true)"
  [ -z "$privileged" ] || fail "setuid/setgid files: $privileged"
  pass "no setuid or setgid files"

  writable="$(find / -xdev ! -type l -perm -0002 ! -perm -1000 2>/dev/null || true)"
  [ -z "$writable" ] || fail "world-writable paths: $writable"
  pass "no world-writable paths (other than sticky directories)"

  [ ! -e /etc/shadow ] || fail "/etc/shadow is present"
  pass "no password database (/etc/shadow)"
fi

# Dev variants ship install-packages for building app-specific distroless runtimes.
if [ ! -d /var/lib/dpkg/status.d ]; then
  command -v install-packages >/dev/null 2>&1 || fail "install-packages missing from the dev variant"
  pass "install-packages is available"
fi

id nonroot >/dev/null 2>&1 || fail "nonroot user missing"
[ "$(id -u nonroot)" = "65532" ] || fail "nonroot UID is not 65532"
pass "nonroot user (UID 65532) exists"

fips_version="$(echo "$providers" | grep -A2 "^  fips" | sed -n 's/^ *version: //p')"
if [ "$(printf '%s\n3.5\n' "$fips_version" | sort -V | head -n1)" = "3.5" ]; then
  openssl genpkey -algorithm ML-DSA-65 -out "$tmp/mldsa.key" \
    || fail "ML-DSA-65 key generation failed"
  echo test > "$tmp/msg"
  if ! {
    openssl pkeyutl -sign -rawin -inkey "$tmp/mldsa.key" -in "$tmp/msg" -out "$tmp/sig" &&
      openssl pkeyutl -verify -rawin -inkey "$tmp/mldsa.key" -in "$tmp/msg" \
        -sigfile "$tmp/sig" >/dev/null
  }; then
    fail "ML-DSA-65 sign/verify failed"
  fi
  pass "ML-DSA-65 sign/verify works"

  if ! {
    openssl genpkey -algorithm ML-KEM-768 -out "$tmp/mlkem.key" &&
      openssl pkeyutl -encap -inkey "$tmp/mlkem.key" -out "$tmp/ct" -secret "$tmp/ss1" &&
      openssl pkeyutl -decap -inkey "$tmp/mlkem.key" -in "$tmp/ct" -secret "$tmp/ss2" &&
      cmp -s "$tmp/ss1" "$tmp/ss2"
  }; then
    fail "ML-KEM-768 encap/decap failed"
  fi
  pass "ML-KEM-768 encap/decap works"

  openssl s_server -quiet -accept 127.0.0.1:8443 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
    -tls1_3 -groups SecP256r1MLKEM768 >/dev/null 2>&1 &
  server_pids="$server_pids $!"
  sleep 1
  handshake="$(echo Q | openssl s_client -connect 127.0.0.1:8443 -tls1_3 \
    -groups SecP256r1MLKEM768 -brief 2>&1)" || fail "hybrid PQC TLS handshake failed: $handshake"
  echo "$handshake" | grep -q 'SecP256r1MLKEM768' || fail "TLS did not negotiate SecP256r1MLKEM768"
  pass "TLS 1.3 negotiates hybrid SecP256r1MLKEM768"
else
  openssl genpkey -algorithm ML-KEM-768 >/dev/null 2>&1 \
    && fail "ML-KEM available from a pre-3.5 FIPS provider"
  pass "FIPS provider $fips_version has no PQC (expected)"
fi

echo "All FIPS checks passed."
