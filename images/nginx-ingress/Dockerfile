# syntax=docker/dockerfile:1

# F5 NGINX Ingress Controller (NGINX OSS) on the FIPS base images.
#
# Built from the upstream kubernetes-ingress source release, following its
# `debian` image target, with three differences:
#   - the controller is compiled by debian-fips-go (Go Cryptographic Module,
#     GOFIPS140=certified), so its TLS to the Kubernetes API is FIPS;
#   - NGINX links Debian's OpenSSL, which the base routes through the OpenSSL
#     FIPS provider (3.1.2 on latest, 3.5.4 with ML-KEM on -pqc);
#   - the main template defaults to AES-256-GCM for client TLS 1.2, and
#     fips-tls-policy.conf enforces it for backend TLS (nginx.tmpl.patch).
# NGINX Agent is not included.
#
# Targets:
#   runtime  Distroless base + NGINX with the njs, otel and acme modules (the
#            ones the controller loads) + the controller. Published as latest.
#   dev      Dev base + NGINX with all upstream modules + the controller.
#            Published as latest-dev.
#   test     runtime + busybox + openssl CLI for the test suite. Not published.

ARG BASE_IMAGE=debian-fips-base:latest
ARG BASE_DEV_IMAGE=debian-fips-base:latest-dev
ARG BASE_TEST_IMAGE=debian-fips-base:test
ARG GO_IMAGE=debian-fips-go:latest
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# ---------------------------------------------------------------------------
# Download and verify the controller source; apply the TLS policy patch.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS source

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NIC_VERSION=5.6.3

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl patch \
 && rm -rf /var/lib/apt/lists/*

COPY images/nginx-ingress/nginx.tmpl.patch /tmp/nginx.tmpl.patch
WORKDIR /src
RUN case "${NIC_VERSION}" in \
      5.6.3) sha256=81424546e74c95ca5215ce00f8feebea1ea931049d86c2e3688c4292b27565c1 ;; \
      *) echo "Unsupported NIC_VERSION: ${NIC_VERSION}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/src.tar.gz \
      "https://github.com/nginx/kubernetes-ingress/archive/refs/tags/v${NIC_VERSION}.tar.gz" \
 && echo "${sha256}  /tmp/src.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/src.tar.gz --strip-components=1 \
 && patch -p1 --forward < /tmp/nginx.tmpl.patch

# ---------------------------------------------------------------------------
# Controller: static binary from the FIPS Go toolchain.
# ---------------------------------------------------------------------------
FROM ${GO_IMAGE} AS controller

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NIC_VERSION=5.6.3
ARG TARGETARCH

# GOTOOLCHAIN=local keeps the FIPS toolchain; the build fails rather than
# downloading a different Go if go.mod ever requires one.
ENV GOTOOLCHAIN=local

COPY --from=source /src /go/src/kubernetes-ingress
WORKDIR /go/src/kubernetes-ingress
RUN go build -trimpath -ldflags "-s -w -X main.version=${NIC_VERSION}" \
      -o /nginx-ingress ./cmd/nginx-ingress \
 && go version -m /nginx-ingress | grep -q 'GOFIPS140=v1.0.0'

# ---------------------------------------------------------------------------
# dev: NGINX with every upstream module, the controller and its templates.
# ---------------------------------------------------------------------------
FROM ${BASE_DEV_IMAGE} AS dev

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NIC_VERSION=5.6.3
ARG NGINX_VERSION=1.31.6
ARG NGINX_MODULES="nginx-module-njs nginx-module-otel nginx-module-acme nginx-module-xslt nginx-module-geoip nginx-module-image-filter"

LABEL org.opencontainers.image.title="debian-fips-nginx-ingress" \
      org.opencontainers.image.description="F5 NGINX Ingress Controller ${NIC_VERSION} (NGINX ${NGINX_VERSION}) with TLS through the OpenSSL FIPS provider (dev variant: all modules, shell and apt)" \
      org.opencontainers.image.version="${NIC_VERSION}"

# nginx.org's signing keys, checked against their published fingerprints.
# The repository is fetched over http, like Debian's own sources: apt
# authenticates packages by the repository signature, and over https the
# FIPS provider breaks apt for repositories that list MD5 checksums (apt's
# refused MD5 attempt surfaces as a TLS read error). UID/GID 101 matches the
# upstream controller image.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl gpg libcap2-bin \
 && curl -fsSLo /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key \
 && gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg /tmp/nginx_signing.key \
 && gpg --show-keys --with-colons /usr/share/keyrings/nginx-archive-keyring.gpg \
      | awk -F: '/^fpr/ {print $10}' | sort > /tmp/fingerprints \
 && printf '%s\n' 573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62 8540A6F18833A80E9C1653A42FD21310B49F6B46 \
      9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3 | sort | diff - /tmp/fingerprints \
 && echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian trixie nginx" \
      > /etc/apt/sources.list.d/nginx.list \
 && printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n' \
      > /etc/apt/preferences.d/99nginx \
 && groupadd --system --gid 101 nginx \
 && useradd --system --gid nginx --no-create-home --home-dir /nonexistent \
      --comment "nginx user" --shell /bin/false --uid 101 nginx \
 && apt-get update \
 && modules="$(for m in ${NGINX_MODULES}; do printf '%s=%s* ' "$m" "${NGINX_VERSION}"; done)" \
 && eval "apt-get install -y --no-install-recommends nginx=${NGINX_VERSION}* ${modules}" \
 && apt-get purge -y --auto-remove gpg curl \
 && rm -rf /var/lib/apt/lists/* /tmp/nginx_signing.key /tmp/fingerprints

COPY --from=controller /nginx-ingress /nginx-ingress
COPY --from=source /src/internal/configs/version1/nginx.tmpl /src/internal/configs/version1/nginx.ingress.tmpl /
COPY --from=source /src/internal/configs/version2/nginx.virtualserver.tmpl /src/internal/configs/version2/nginx.transportserver.tmpl /
COPY --from=source /src/internal/configs/njs/ /etc/nginx/njs/
COPY images/nginx-ingress/fips-tls-policy.conf /etc/nginx/fips-tls-policy.conf

# The same layout and capabilities as the upstream image (build/scripts/common.sh).
RUN mkdir -p /var/lib/nginx /etc/nginx/secrets /etc/nginx/stream-conf.d \
 && setcap 'cap_net_bind_service=+eip' /usr/sbin/nginx \
 && setcap 'cap_net_bind_service=+eip' /usr/sbin/nginx-debug \
 && setcap 'cap_net_bind_service=+ep' /nginx-ingress \
 && rm -f /etc/nginx/conf.d/* \
 && chown -R 101:0 /etc/nginx /var/cache/nginx /var/lib/nginx /var/log/nginx /*.tmpl /nginx-ingress \
 && chmod -R g=u /etc/nginx /var/cache/nginx /var/lib/nginx /var/log/nginx /*.tmpl \
 && ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80 443
STOPSIGNAL SIGTERM
ENTRYPOINT ["/nginx-ingress"]
USER 101

# ---------------------------------------------------------------------------
# rootfs: NGINX, the modules the controller loads, and their libraries.
# ---------------------------------------------------------------------------
FROM dev AS rootfs

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER 0

# libedit2 and its dependencies keep the njs package's CLI intact.
RUN install-packages /rootfs \
      nginx nginx-module-njs nginx-module-otel nginx-module-acme \
      libpcre2-8-0 libcrypt1 libxml2 liblzma5 libcares2 libstdc++6 \
      libedit2 libbsd0 libmd0 libtinfo6 \
 && mkdir -p /rootfs/var/lib /rootfs/var/cache /rootfs/var/log \
 && cp -a /var/lib/nginx /rootfs/var/lib/ \
 && cp -a /var/cache/nginx /rootfs/var/cache/ \
 && cp -a /var/log/nginx /rootfs/var/log/ \
 && rm -rf /rootfs/etc/nginx \
 && cp -a /etc/nginx /rootfs/etc/ \
 && cp -a /nginx-ingress /*.tmpl /rootfs/ \
 && cp -a /usr/sbin/nginx /usr/sbin/nginx-debug /rootfs/usr/sbin/ \
 && printf '%s\n' 'root:x:0:0:root:/root:/sbin/nologin' \
      'nonroot:x:65532:65532:nonroot:/home/nonroot:/sbin/nologin' \
      'nginx:x:101:101:nginx user:/nonexistent:/sbin/nologin' > /rootfs/etc/passwd \
 && printf '%s\n' 'root:x:0:' 'nonroot:x:65532:' 'nginx:x:101:' > /rootfs/etc/group

USER 101

# ---------------------------------------------------------------------------
# runtime: distroless.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS runtime

ARG NIC_VERSION=5.6.3
ARG NGINX_VERSION=1.31.6

LABEL org.opencontainers.image.title="debian-fips-nginx-ingress" \
      org.opencontainers.image.description="Distroless F5 NGINX Ingress Controller ${NIC_VERSION} (NGINX ${NGINX_VERSION}) with TLS through the OpenSSL FIPS provider" \
      org.opencontainers.image.version="${NIC_VERSION}"

COPY --from=rootfs /rootfs/ /

EXPOSE 80 443
STOPSIGNAL SIGTERM
ENTRYPOINT ["/nginx-ingress"]
USER 101

# ---------------------------------------------------------------------------
# test: runtime + busybox + openssl CLI. Never published.
# ---------------------------------------------------------------------------
FROM ${BASE_TEST_IMAGE} AS test-tools

FROM runtime AS test

COPY --from=test-tools /bin/busybox /bin/busybox
COPY --from=test-tools /usr/bin/openssl /usr/bin/openssl

USER 0
RUN ["/bin/busybox", "--install", "-s", "/bin"]
USER 101
ENTRYPOINT []

# ---------------------------------------------------------------------------
# Default target for a plain `docker build`: the distroless runtime.
# ---------------------------------------------------------------------------
FROM runtime
