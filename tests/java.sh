#!/bin/sh
# Verifies Java's cryptography and TLS run only through Bouncy Castle FIPS.
# Run inside the Java image:
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> /tests/java.sh
#
# The distroless :test image ships a prebuilt check program; the JDK (dev)
# image compiles it from tests/java.
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

tmp="$(mktemp -d)"
server_pids=""
trap 'kill $server_pids 2>/dev/null; rm -rf "$tmp"' EXIT

# JAVA_TOOL_OPTIONS makes every JVM print a "Picked up" line on stderr.
java_quiet() { java "$@" 2> "$tmp/stderr"; status=$?; grep -v '^Picked up JAVA_TOOL_OPTIONS' "$tmp/stderr" >&2 || true; return $status; }

if [ -f /opt/fipscheck/fipscheck.jar ]; then
  jar=/opt/fipscheck/fipscheck.jar
else
  javac -cp /usr/share/java/bc-fips/bc-fips.jar -d "$tmp/classes" /tests/java/FipsCheck.java 2>/dev/null || fail "compiling the check program"
  jar --create --file "$tmp/fipscheck.jar" --main-class FipsCheck -C "$tmp/classes" . \
    || fail "packaging the check program"
  jar="$tmp/fipscheck.jar"
fi

pass "$(java -version 2>&1 | grep -v 'Picked up' | head -n1)"
java_quiet -jar "$jar" crypto || fail "crypto checks"

openssl req -x509 -newkey EC -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
  -subj /CN=localhost -keyout "$tmp/tls.key" -out "$tmp/tls.crt" 2>/dev/null
openssl s_server -quiet -accept 127.0.0.1:8443 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  >/dev/null 2>&1 &
server_pids="$server_pids $!"
openssl s_server -quiet -accept 127.0.0.1:8444 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  -ciphersuites TLS_AES_128_GCM_SHA256 -cipher ECDHE-ECDSA-AES128-GCM-SHA256 >/dev/null 2>&1 &
server_pids="$server_pids $!"
sleep 1

result="$(java_quiet -jar "$jar" tls 8443)" || fail "Java TLS handshake failed"
[ "$result" = "TLS_AES_256_GCM_SHA384 BCJSSE" ] || fail "Java negotiated '$result'"
pass "Java TLS (BCJSSE) negotiates AES-256 by default"
java_quiet -jar "$jar" tls 8444 >/dev/null 2>&1 && fail "Java accepted an AES-128-only server"
pass "Java TLS refuses AES-128-only servers"

echo "All Java FIPS checks passed."
