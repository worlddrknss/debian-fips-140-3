# syntax=docker/dockerfile:1

# Node.js on the FIPS base image.
#
# The official Node.js binaries statically link their own OpenSSL, which
# bypasses the system FIPS provider. This image compiles Node.js with
# --shared-openssl so it uses the base image's libcrypto and, through
# /etc/ssl/openssl.cnf (nodejs_conf section), the FIPS provider.

ARG BASE_IMAGE=debian-fips-base:latest
# Same pinned Debian image the base is built from, so libssl-dev here matches
# the base image's libssl3t64. Building from Debian rather than the base keeps
# changes to the base's FIPS configuration from forcing a Node.js recompile.
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# ---------------------------------------------------------------------------
# Build Node.js against the system OpenSSL.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS node-builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NODE_VERSION=24.21.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl libssl-dev python3 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN case "${NODE_VERSION}" in \
      24.21.0) sha256=622424efb5dc0c26c93fbb619ff10737ee289c605b837c88778e186925d82777 ;; \
      *) echo "Unsupported NODE_VERSION: ${NODE_VERSION}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo node.tar.gz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}.tar.gz" \
 && echo "${sha256}  node.tar.gz" | sha256sum -c - \
 && tar -xzf node.tar.gz --strip-components=1 \
 && rm node.tar.gz

RUN ./configure --prefix=/usr/local --shared-openssl --openssl-use-def-ca-store \
 && make -j"$(nproc)" \
 && make install DESTDIR=/out

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE}

ARG NODE_VERSION=24.21.0
# The npm bundled with Node.js lags behind npm's own security fixes, so a newer
# npm within the same major version is installed over it.
ARG NPM_VERSION=11.20.0

LABEL org.opencontainers.image.title="debian-fips-node" \
      org.opencontainers.image.description="Node.js ${NODE_VERSION} linked to the system OpenSSL FIPS configuration"

COPY --from=node-builder /out/usr/local/ /usr/local/

RUN npm install -g "npm@${NPM_VERSION}" \
 && npm cache clean --force \
 && rm -rf /root/.npm

# Node.js sets its own cipher list and ignores the system CipherString, so the
# 256-bit-only policy from /etc/ssl/openssl.cnf is repeated here. Images that
# set NODE_OPTIONS must keep these flags.
ENV NODE_OPTIONS="--tls-min-v1.2 --tls-cipher-list=TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"

RUN node -e 'if (require("crypto").getFips() !== 1) process.exit(1)'
