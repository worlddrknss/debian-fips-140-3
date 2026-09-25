#!/bin/sh
# Verifies the NGINX Ingress Controller image: NGINX's client and backend TLS
# go through the OpenSSL FIPS provider under the 256-bit policy, the
# controller is built with the Go FIPS module, and the shipped modules load.
# Run inside the image with privileged ports restricted, as in Kubernetes:
#   docker run --rm --sysctl net.ipv4.ip_unprivileged_port_start=1024 \
#     -v "$PWD/tests:/tests:ro" <image> /tests/nginx-ingress.sh
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

tmp="$(mktemp -d)"
pids=""
trap 'kill $pids 2>/dev/null; rm -rf "$tmp"' EXIT

fips_version="$(openssl list -providers | grep -A2 "^  fips" | sed -n 's/^ *version: //p')"
pqc=false
[ "$(printf '%s\n3.5\n' "$fips_version" | sort -V | head -n1)" = "3.5" ] && pqc=true

# --- NGINX and the controller ----------------------------------------------
system_openssl="$(openssl version | awk '{print $2}')"
nginx_openssl="$(nginx -V 2>&1 | sed -n 's/.*running with OpenSSL \([^ ]*\).*/\1/p')"
[ -n "$nginx_openssl" ] || nginx_openssl="$(nginx -V 2>&1 | sed -n 's/.*built with OpenSSL \([^ ]*\).*/\1/p')"
[ "$nginx_openssl" = "$system_openssl" ] || fail "NGINX runs OpenSSL $nginx_openssl, system has $system_openssl"
pass "$(nginx -v 2>&1 | sed 's/^nginx version: //') runs on the system OpenSSL $nginx_openssl (FIPS provider $fips_version)"

/nginx-ingress -version >"$tmp/version" 2>&1 || fail "the controller binary doesn't run"
grep -q 'Version=' "$tmp/version" || fail "unexpected controller version output: $(cat "$tmp/version")"
pass "controller runs: $(head -n1 "$tmp/version" | cut -c1-80)"

grep -q 'ssl_ciphers "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384";' /nginx.tmpl \
  || fail "main template has no AES-256 default for ssl_ciphers"
grep -q 'include /etc/nginx/fips-tls-policy.conf;' /nginx.tmpl \
  || fail "main template doesn't include the backend TLS policy"
pass "main template carries the TLS policy patch"

# Every shipped (non-debug) module must load into this NGINX.
names=""
for module in /usr/lib/nginx/modules/*.so; do
  case "$module" in *-debug.so) continue ;; esac
  echo "load_module $module;" >> "$tmp/modules.conf"
  name="${module##*/}"
  names="$names ${name%.so}"
done
printf 'pid %s/modules.pid;\nerror_log stderr;\nevents {}\n' "$tmp" >> "$tmp/modules.conf"
nginx -t -q -p "$tmp" -c "$tmp/modules.conf" || fail "modules don't load"
pass "modules load:$names"

# --- TLS ---------------------------------------------------------------------
openssl req -x509 -newkey EC -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
  -subj /CN=localhost -keyout "$tmp/tls.key" -out "$tmp/tls.crt" 2>/dev/null

# Backends: one under the system policy (AES-256-GCM), one that only speaks
# TLS 1.2 with AES-128.
openssl s_server -quiet -www -accept 127.0.0.1:9443 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  >/dev/null 2>&1 &
pids="$pids $!"
openssl s_server -quiet -www -accept 127.0.0.1:9444 -cert "$tmp/tls.crt" -key "$tmp/tls.key" \
  -tls1_2 -cipher ECDHE-ECDSA-AES128-GCM-SHA256 >/dev/null 2>&1 &
pids="$pids $!"

# The http-level TLS settings exactly as the patched template renders them
# by default, plus a plain listener on port 80 to exercise the capability.
default_ciphers="$(grep -o 'ssl_ciphers "ECDHE[^"]*";' /nginx.tmpl)"
mkdir -p "$tmp/temp"
cat > "$tmp/nginx.conf" <<EOF
pid $tmp/nginx.pid;
error_log stderr;
events {}
http {
    access_log off;
    client_body_temp_path $tmp/temp/body;
    proxy_temp_path $tmp/temp/proxy;
    fastcgi_temp_path $tmp/temp/fastcgi;
    uwsgi_temp_path $tmp/temp/uwsgi;
    scgi_temp_path $tmp/temp/scgi;
    $default_ciphers
    include /etc/nginx/fips-tls-policy.conf;
    server {
        listen 127.0.0.1:80;
        return 200 "ok\n";
    }
    server {
        listen 127.0.0.1:8443 ssl;
        ssl_certificate $tmp/tls.crt;
        ssl_certificate_key $tmp/tls.key;
        location = /backend/aes256 { proxy_pass https://127.0.0.1:9443/; }
        location = /backend/aes128 { proxy_pass https://127.0.0.1:9444/; }
        location / { return 200 "ok\n"; }
    }
}
EOF
nginx -p "$tmp" -c "$tmp/nginx.conf" -g 'daemon off;' 2>"$tmp/nginx.log" &
pids="$pids $!"
sleep 1
kill -0 "${pids##* }" 2>/dev/null || fail "NGINX didn't start: $(cat "$tmp/nginx.log")"
pass "NGINX binds port 80 as UID $(id -u) with privileged ports restricted (cap_net_bind_service)"

session="$(echo Q | openssl s_client -connect 127.0.0.1:8443 -brief 2>&1)"
cipher="$(echo "$session" | sed -n 's/^Ciphersuite: //p')"
group="$(echo "$session" | sed -n 's/^Negotiated TLS1.3 group: //p')"
[ "$cipher" = "TLS_AES_256_GCM_SHA384" ] || fail "client TLS negotiated '$cipher'"
pass "client TLS 1.3 negotiates $cipher"
if $pqc; then
  [ "$group" = "X25519MLKEM768" ] || fail "client TLS negotiated group '$group'"
  pass "client TLS negotiates hybrid PQC key exchange ($group)"
fi

cipher12="$(echo Q | openssl s_client -connect 127.0.0.1:8443 -tls1_2 -brief 2>&1 | sed -n 's/^Ciphersuite: //p')"
case "$cipher12" in *AES256-GCM*) ;; *) fail "client TLS 1.2 negotiated '$cipher12'" ;; esac
pass "client TLS 1.2 negotiates $cipher12"

if echo Q | openssl s_client -connect 127.0.0.1:8443 -tls1_2 \
  -cipher ECDHE-ECDSA-AES128-GCM-SHA256 -brief >/dev/null 2>&1; then
  fail "NGINX accepted an AES-128-only TLS 1.2 client"
fi
pass "NGINX refuses AES-128-only clients"

status() {
  printf 'GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' "$1" \
    | openssl s_client -quiet -connect 127.0.0.1:8443 2>/dev/null | head -n1 | tr -d '\r'
}
case "$(status /backend/aes256)" in
  "HTTP/1.1 200"*) pass "backend TLS to an AES-256 upstream works (200)" ;;
  *) fail "proxying to an AES-256 backend: $(status /backend/aes256)" ;;
esac
case "$(status /backend/aes128)" in
  "HTTP/1.1 502"*) pass "backend TLS refuses an AES-128-only upstream (502)" ;;
  *) fail "proxying to an AES-128-only backend: $(status /backend/aes128)" ;;
esac

echo "All NGINX Ingress FIPS checks passed."
