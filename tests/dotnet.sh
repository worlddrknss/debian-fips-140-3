#!/bin/sh
# Verifies .NET's cryptography and TLS run through the OpenSSL FIPS provider.
# Run inside the .NET image:
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> /tests/dotnet.sh
#
# The distroless :test image ships a prebuilt check program; the SDK (dev)
# image builds it from tests/dotnet.
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

tmp="$(mktemp -d)"
server_pids=""
trap 'kill $server_pids 2>/dev/null; rm -rf "$tmp"' EXIT

if [ -f /opt/fipscheck/fipscheck.dll ]; then
  check="dotnet /opt/fipscheck/fipscheck.dll"
else
  cp -r /tests/dotnet "$tmp/src"
  dotnet publish "$tmp/src" -c Release -o "$tmp/fipscheck" --nologo -v quiet >/dev/null \
    || fail "building the check program"
  check="dotnet $tmp/fipscheck/fipscheck.dll"
fi

pass ".NET runtime $(dotnet --list-runtimes | awk '/NETCore.App/ {print $2; exit}')"

$check crypto || fail "crypto checks"

openssl req -x509 -newkey EC -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
  -subj /CN=localhost -keyout "$tmp/tls.key" -out "$tmp/tls.crt" 2>/dev/null
openssl s_server -quiet -accept 127.0.0.1:8443 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  >/dev/null 2>&1 &
server_pids="$server_pids $!"
openssl s_server -quiet -accept 127.0.0.1:8444 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  -ciphersuites TLS_AES_128_GCM_SHA256 -cipher ECDHE-ECDSA-AES128-GCM-SHA256 >/dev/null 2>&1 &
server_pids="$server_pids $!"
sleep 1

cipher="$($check tls 8443)" || fail ".NET TLS handshake failed"
[ "$cipher" = "TLS_AES_256_GCM_SHA384" ] || fail ".NET negotiated $cipher"
pass ".NET SslStream negotiates AES-256 by default"
$check tls 8444 >/dev/null 2>&1 && fail ".NET accepted an AES-128-only server"
pass ".NET SslStream refuses AES-128-only servers"

echo "All .NET FIPS checks passed."
